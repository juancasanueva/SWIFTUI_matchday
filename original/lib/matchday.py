#!/usr/bin/env python3
"""Fixtures, live scores, tables and where-to-watch for the grivera.matchday
Omarchy plugin. Covers LaLiga, Serie A, the Premier League, MLS and the UEFA
Nations League and Champions League.

Data comes from ESPN's public site API (no key). "Where to watch" uses ESPN's
per-match US listings when they exist and otherwise a per-country rights table
(broadcasters.json, which ~/.config/grivera-matchday/broadcasters.json can
override). The country comes from the system timezone unless you pick one.

Standard library only.

  matchday status [--json]    favorites' next matches and today's games
  matchday next               one line: your next (or live) match
  matchday daemon             JSON state lines on stdout, commands on stdin
"""

import concurrent.futures
import datetime
import json
import os
import re
import shutil
import string
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import zlib

HOME = os.path.expanduser("~")
STATE_DIR = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local/state"), "grivera-matchday")
CACHE_DIR = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.join(HOME, ".cache"), "grivera-matchday")
USER_DIR = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config"), "grivera-matchday")
CONFIG_FILE = os.path.join(STATE_DIR, "config.json")
NOTIFIED_FILE = os.path.join(STATE_DIR, "notified.json")
HTTP_DIR = os.path.join(CACHE_DIR, "http")
LOGO_DIR = os.path.join(CACHE_DIR, "logos")
LIB = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(os.path.dirname(LIB), "assets")

API = "https://site.api.espn.com/apis/site/v2/sports/soccer"
STANDINGS_API = "https://site.api.espn.com/apis/v2/sports/soccer"
LOGO_URL = "https://a.espncdn.com/combiner/i?img=/i/%s/soccer/%s/%s.png&w=128&h=128"
UA = "grivera-matchday/1.0"

LEAGUES = [
    {"id": "esp.1", "name": "LaLiga", "short": "LaLiga", "country": "Spain", "color": "#ff4b44", "logoId": "15"},
    {"id": "ita.1", "name": "Serie A", "short": "Serie A", "country": "Italy", "color": "#1aa0e8", "logoId": "12"},
    {"id": "eng.1", "name": "Premier League", "short": "Premier", "country": "England", "color": "#a26bfa", "logoId": "23"},
    {"id": "usa.1", "name": "MLS", "short": "MLS", "country": "USA & Canada", "color": "#36c46f", "logoId": "19"},
    {"id": "uefa.champions", "name": "UEFA Champions League", "short": "UCL", "country": "Europe", "color": "#5865f2", "logoId": "2"},
    {"id": "uefa.nations", "name": "UEFA Nations League", "short": "Nations", "country": "Europe", "color": "#f2b705",
     "logoId": "2395", "national": True},
]
LEAGUE_BY_ID = {l["id"]: l for l in LEAGUES}

DEFAULT_CONFIG = {
    "favorites": [],              # [{league, id, name, short, abbr}]
    "leagues": [l["id"] for l in LEAGUES],
    "country": "auto",            # "auto" = from the timezone, else ISO code
    "spanish": True,              # include Spanish-language broadcasts
    "notifyKickoff": True,
    "kickoffLead": 15,            # minutes before kickoff
    "notifyGoals": True,
    "notifyFinal": True,
    "barScore": True,             # live score text next to the bar icon
}

DAYS_BACK = 3
DAYS_AHEAD = 9
TICK = 5


# ---------------------------------------------------------------- helpers

def load_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def save_json(path, data, indent=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = "%s.%d.tmp" % (path, threading.get_ident())
    with open(tmp, "w") as f:
        json.dump(data, f, indent=indent, separators=None if indent else (",", ":"))
    os.replace(tmp, path)


MAX_BODY = 16 * 1024 * 1024   # ESPN scoreboards run ~1 MB, logos far less


class BodylessRedirectHandler(urllib.request.HTTPRedirectHandler):
    """Follow HTTP redirects without buffering their untrusted response bodies."""

    def http_error_302(self, req, fp, code, msg, headers):
        try:
            location = (headers.get("location") or headers.get("Location")
                        or headers.get("uri") or headers.get("URI"))
            if not location:
                return None
            parts = urllib.parse.urlparse(location)
            if parts.scheme not in ("", "http", "https"):
                raise ValueError("unsupported redirect scheme")
            if not parts.path and parts.netloc:
                parts = parts._replace(path="/")
            location = urllib.parse.quote(
                urllib.parse.urlunparse(parts), encoding="iso-8859-1", safe=string.punctuation
            )
            newurl = urllib.parse.urljoin(req.full_url, location)
            if urllib.parse.urlparse(req.full_url).scheme == "https" and urllib.parse.urlparse(newurl).scheme != "https":
                raise ValueError("insecure redirect")
            new = self.redirect_request(req, fp, code, msg, headers, newurl)
            if new is None:
                return None
            if hasattr(req, "redirect_dict"):
                visited = new.redirect_dict = req.redirect_dict
                if visited.get(newurl, 0) >= self.max_repeats or len(visited) >= self.max_redirections:
                    raise ValueError("too many redirects")
            else:
                visited = new.redirect_dict = req.redirect_dict = {}
            visited[newurl] = visited.get(newurl, 0) + 1
        finally:
            # urllib's default handler calls fp.read() here. A streaming 30x
            # body can exhaust memory or stall forever; no body is needed.
            fp.close()
        return self.parent.open(new, timeout=req.timeout)

    http_error_301 = http_error_303 = http_error_307 = http_error_308 = http_error_302


HTTP_OPENER = urllib.request.build_opener(BodylessRedirectHandler)


def gunzip(data, limit=MAX_BODY):
    out = zlib.decompressobj(31).decompress(data, limit + 1)
    if len(out) > limit:
        raise ValueError("response too large")
    return out


def http_get(url, timeout=12):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept-Encoding": "gzip"})
    with HTTP_OPENER.open(req, timeout=timeout) as r:
        data = r.read(MAX_BODY + 1)
    if len(data) > MAX_BODY:
        raise ValueError("response too large")
    if data[:2] == b"\x1f\x8b":
        data = gunzip(data)
    return data


def http_json(url):
    data = json.loads(http_get(url))
    if isinstance(data, dict) and data.get("code") and data.get("message") and len(data) <= 3:
        raise ValueError("ESPN: %s" % data["message"])
    return data


def parse_ts(s):
    if not s:
        return 0
    try:
        s = s.replace("Z", "+00:00")
        if len(s) == 22 and s[16] == "+":      # 2026-10-10T11:30+00:00 (no seconds)
            s = s[:16] + ":00" + s[16:]
        return datetime.datetime.fromisoformat(s).timestamp()
    except ValueError:
        return 0


def local_today():
    return datetime.date.today()


# ---------------------------------------------------------------- location

def system_timezone():
    tz = os.environ.get("TZ", "").lstrip(":")
    if tz and "/" in tz:
        return tz
    try:
        link = os.readlink("/etc/localtime")
        if "zoneinfo/" in link:
            return link.split("zoneinfo/", 1)[1]
    except OSError:
        pass
    return ""


def detect_location():
    tz = system_timezone()
    code = ""
    for tab in ("zone1970.tab", "zone.tab"):
        try:
            with open(os.path.join("/usr/share/zoneinfo", tab)) as f:
                for line in f:
                    if line.startswith("#"):
                        continue
                    parts = line.rstrip("\n").split("\t")
                    if len(parts) >= 3 and parts[2] == tz:
                        code = parts[0].split(",")[0]
                        break
        except OSError:
            continue
        if code:
            break
    city = tz.rsplit("/", 1)[-1].replace("_", " ") if tz else ""
    return {"timezone": tz, "country": code, "city": city}


# ---------------------------------------------------------------- broadcasters

def load_rights():
    base = load_json(os.path.join(LIB, "broadcasters.json"), {})
    user = load_json(os.path.join(USER_DIR, "broadcasters.json"), {})
    for key in ("services", "countries", "everywhere", "espnAliases"):
        merged = dict(base.get(key) or {})
        for k, v in (user.get(key) or {}).items():
            if key == "countries" and isinstance(v, dict) and isinstance(merged.get(k), dict):
                merged[k] = dict(merged[k], **v)
            else:
                merged[k] = v
        base[key] = merged
    return base


def service(rights, sid):
    s = (rights.get("services") or {}).get(sid)
    if s:
        return dict(s, id=sid)
    return {"id": sid, "name": sid, "url": "", "color": "", "kind": "tv"}


def where_to_watch(ev, country, config, rights):
    league = ev["league"]
    services, source, verified = [], "rights", True
    if country == "US" and ev.get("tv"):
        aliases = rights.get("espnAliases") or {}
        for name in ev["tv"]:
            sid = aliases.get(name.strip().lower())
            services.append(service(rights, sid) if sid else {"id": name, "name": name, "url": "", "color": "", "kind": "tv"})
        source = "espn"
    else:
        entry = ((rights.get("countries") or {}).get(country) or {}).get(league)
        if entry is None:
            entry = (rights.get("everywhere") or {}).get(league)
        if isinstance(entry, dict):
            verified = entry.get("verified", True)
            # National-team rights often follow who's playing: England on ITV,
            # Scotland on BBC, everyone else on the league-wide holder.
            by_team = entry.get("teams") or {}
            picked = [sid for side in ("home", "away") for sid in by_team.get(ev[side]["abbr"], [])]
            entry = picked or entry.get("services") or []
        services = [service(rights, s) for s in entry or []]
    if not config.get("spanish", True):
        kept = [s for s in services if s.get("lang") != "es"]
        services = kept or services
    seen, out = set(), []
    for s in services:
        if s["id"] not in seen:
            seen.add(s["id"])
            out.append(s)
    return {"source": source, "verified": verified, "services": out}


# ---------------------------------------------------------------- cache

class Store:
    """Fetched JSON keyed by job, mirrored to disk so restarts are instant."""

    def __init__(self):
        self.lock = threading.Lock()
        self.items = {}       # key -> {"at": ts, "data": obj}
        self.failed = {}      # key -> ts of last failure
        os.makedirs(HTTP_DIR, exist_ok=True)
        for name in os.listdir(HTTP_DIR):
            if name.endswith(".json"):
                item = load_json(os.path.join(HTTP_DIR, name), None)
                if isinstance(item, dict) and "data" in item:
                    self.items[name[:-5]] = item

    @staticmethod
    def path(key):
        return os.path.join(HTTP_DIR, key.replace(":", "_").replace("/", "_") + ".json")

    def get(self, key):
        with self.lock:
            item = self.items.get(key)
        return item["data"] if item else None

    def age(self, key):
        with self.lock:
            item = self.items.get(key)
            fail = self.failed.get(key, 0)
        now = time.time()
        if now - fail < 60:          # back off a minute after an error
            return 0
        return now - item["at"] if item else float("inf")

    def put(self, key, data):
        item = {"at": time.time(), "data": data}
        with self.lock:
            self.items[key] = item
            self.failed.pop(key, None)
        try:
            save_json(self.path(key), dict(item, key=key))
        except OSError:
            pass

    def fail(self, key):
        with self.lock:
            self.failed[key] = time.time()

    def expire(self, prefix=""):
        with self.lock:
            for key, item in self.items.items():
                if key.startswith(prefix):
                    item["at"] = 0
            self.failed.clear()

    def prune(self, keep):
        with self.lock:
            stale = [k for k in self.items if k.startswith("sb:") and k not in keep]
            for k in stale:
                del self.items[k]
        for k in stale:
            try:
                os.remove(self.path(k))
            except OSError:
                pass


# ---------------------------------------------------------------- normalizing

def team_of(comp):
    t = comp.get("team") or {}
    score = comp.get("score")
    if isinstance(score, dict):
        score = score.get("displayValue")
    rec = comp.get("records") or comp.get("record") or []
    record = (rec[0].get("summary") or rec[0].get("displayValue") or "") if rec else ""
    color = t.get("color") or ""
    return {
        "id": str(t.get("id") or comp.get("id") or ""),
        "name": t.get("displayName") or t.get("name") or "",
        "short": t.get("shortDisplayName") or t.get("displayName") or "",
        "abbr": t.get("abbreviation") or "",
        "color": ("#" + color) if color and not color.startswith("#") else color,
        "score": None if score in (None, "") else str(score),
        "winner": bool(comp.get("winner")),
        "form": comp.get("form") or "",
        "record": record,
    }


def norm_event(e, league):
    c = (e.get("competitions") or [{}])[0]
    st = c.get("status") or e.get("status") or {}
    typ = st.get("type") or {}
    comps = c.get("competitors") or []
    home = next((x for x in comps if x.get("homeAway") == "home"), comps[0] if comps else {})
    away = next((x for x in comps if x.get("homeAway") == "away"), comps[1] if len(comps) > 1 else {})

    plays = []
    for d in c.get("details") or []:
        if not (d.get("scoringPlay") or d.get("redCard")):
            continue
        ath = (d.get("athletesInvolved") or [{}])[0]
        plays.append({
            "team": str((d.get("team") or {}).get("id") or ""),
            "player": ath.get("shortName") or ath.get("displayName") or "",
            "minute": (d.get("clock") or {}).get("displayValue") or "",
            "goal": bool(d.get("scoringPlay")),
            "og": bool(d.get("ownGoal")),
            "pen": bool(d.get("penaltyKick")),
            "red": bool(d.get("redCard")) and not d.get("scoringPlay"),
        })

    tv = []
    for g in c.get("geoBroadcasts") or []:
        name = (g.get("media") or {}).get("shortName")
        if name and name not in tv:
            tv.append(name)
    if not tv:
        for b in c.get("broadcasts") or []:
            names = b.get("names") or ([(b.get("media") or {}).get("shortName")] if b.get("region", "us") == "us" else [])
            for n in names:
                if n and n not in tv:
                    tv.append(n)

    url = ""
    for link in e.get("links") or []:
        if "/match/" in (link.get("href") or ""):
            url = link["href"]
            break
    venue = c.get("venue") or {}
    addr = venue.get("address") or {}
    return {
        "id": str(e.get("id")),
        "league": league,
        "date": e.get("date") or c.get("date") or "",
        "ts": parse_ts(e.get("date") or c.get("date")),
        "state": typ.get("state") or "pre",
        "status": typ.get("name") or "",
        "detail": typ.get("shortDetail") or typ.get("detail") or "",
        "clock": st.get("displayClock") or "",
        "completed": bool(typ.get("completed")),
        "home": team_of(home),
        "away": team_of(away),
        "venue": venue.get("fullName") or "",
        "city": addr.get("city") or "",
        "plays": plays,
        "tv": tv,
        "url": url or "https://www.espn.com/soccer/match/_/gameId/%s" % e.get("id"),
        "round": (e.get("week") or {}).get("number") or "",
    }


def norm_table(data):
    groups = []
    children = data.get("children") or [data]
    for child in children:
        rows = []
        for en in (child.get("standings") or {}).get("entries") or []:
            stats = {s.get("name"): s.get("displayValue", s.get("value")) for s in en.get("stats") or []}
            t = en.get("team") or {}
            note = en.get("note") or {}
            rows.append({
                "rank": int(float(stats.get("rank") or 0)),
                "id": str(t.get("id") or ""),
                "name": t.get("displayName") or "",
                "short": t.get("shortDisplayName") or t.get("displayName") or "",
                "abbr": t.get("abbreviation") or "",
                "played": stats.get("gamesPlayed") or "0",
                "w": stats.get("wins") or "0",
                "d": stats.get("ties") or "0",
                "l": stats.get("losses") or "0",
                "gd": stats.get("pointDifferential") or "0",
                "pts": stats.get("points") or "0",
                "note": {"color": note.get("color") or "", "text": note.get("description") or ""} if note else None,
            })
        rows.sort(key=lambda r: r["rank"] or 99)
        groups.append({"name": child.get("name") or "" if len(children) > 1 else "", "rows": rows})
    return groups


def norm_teams(data):
    out = []
    try:
        teams = data["sports"][0]["leagues"][0]["teams"]
    except (KeyError, IndexError, TypeError):
        return out
    for item in teams:
        t = item.get("team") or {}
        color = t.get("color") or ""
        out.append({
            "id": str(t.get("id")),
            "name": t.get("displayName") or "",
            "short": t.get("shortDisplayName") or t.get("displayName") or "",
            "abbr": t.get("abbreviation") or "",
            "color": ("#" + color) if color else "",
        })
    out.sort(key=lambda t: t["short"].lower())
    return out


# ---------------------------------------------------------------- logos

class Logos:
    """Downloads crests into the cache on a background thread."""

    def __init__(self, on_done):
        self.on_done = on_done
        self.lock = threading.Lock()
        self.pending = set()
        self.wake = threading.Event()
        os.makedirs(LOGO_DIR, exist_ok=True)
        threading.Thread(target=self.run, daemon=True).start()

    @staticmethod
    def name(kind, ident, dark):
        return "%s-%s%s.png" % (kind, ident, "-dark" if dark else "")

    def have(self, kind, ident, dark=False):
        n = self.name(kind, ident, dark)
        return n if os.path.exists(os.path.join(LOGO_DIR, n)) else ""

    def want(self, kind, ident):
        if not ident:
            return
        for dark in (False, True):
            n = self.name(kind, ident, dark)
            path = os.path.join(LOGO_DIR, n)
            if os.path.exists(path):
                continue
            miss = path + ".missing"
            if os.path.exists(miss) and time.time() - os.path.getmtime(miss) < 86400:
                continue
            with self.lock:
                self.pending.add((kind, ident, dark))
        self.wake.set()

    def fetch(self, job):
        kind, ident, dark = job
        folder = "teamlogos" if kind == "team" else "leaguelogos"
        path = os.path.join(LOGO_DIR, self.name(kind, ident, dark))
        try:
            data = http_get(LOGO_URL % (folder, "500-dark" if dark else "500", ident), timeout=15)
            if len(data) < 200 or not data.startswith(b"\x89PNG"):
                raise ValueError("not a png")
            with open(path + ".tmp", "wb") as f:
                f.write(data)
            os.replace(path + ".tmp", path)
            return True
        except (OSError, ValueError, urllib.error.URLError):
            try:
                open(path + ".missing", "w").close()
            except OSError:
                pass
            return False

    def run(self):
        with concurrent.futures.ThreadPoolExecutor(6) as pool:
            while True:
                self.wake.wait()
                self.wake.clear()
                with self.lock:
                    jobs, self.pending = list(self.pending), set()
                if jobs and any(pool.map(self.fetch, jobs)):
                    self.on_done()


# ---------------------------------------------------------------- notifications

class Notifier:
    def __init__(self):
        self.ids = {}
        self.mem = load_json(NOTIFIED_FILE, {})
        for k in ("kick", "final", "score"):
            self.mem.setdefault(k, {})

    def save(self):
        cutoff = time.time() - 7 * 86400
        for k in ("kick", "final"):
            self.mem[k] = {i: t for i, t in self.mem[k].items() if t > cutoff}
        self.mem["score"] = {i: v for i, v in self.mem["score"].items() if v[1] > cutoff}
        try:
            save_json(NOTIFIED_FILE, self.mem)
        except OSError:
            pass

    def send(self, key, summary, body, icon="", url="", urgency="normal"):
        if not shutil.which("notify-send"):
            return
        args = ["notify-send", "-a", "Matchday", "-i", icon or os.path.join(ASSETS, "ball.svg"),
                "-u", urgency, "-p", "-h", "string:x-grivera-matchday:" + key]
        if url:
            args += ["-w", "-A", "default=Open match"]
        if key in self.ids:
            args += ["-r", str(self.ids[key])]
        # "--" so ESPN text starting with "-" can't be read as an option
        # (an injected -h could add an omarchy-exec-argv hint).
        args += ["--", summary, body]

        def run():
            try:
                proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
                first = proc.stdout.readline().strip()
                if first.isdigit():
                    self.ids[key] = int(first)
                action = proc.stdout.read().strip()
                proc.wait()
                if action == "default" and url:
                    open_url(url)
            except OSError:
                pass

        threading.Thread(target=run, daemon=True).start()


def open_url(url):
    if not url or not re.match(r"^https?://", url):
        return False
    for cmd in (["omarchy-launch-webapp", url], ["xdg-open", url]):
        if shutil.which(cmd[0]):
            subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            return True
    return False


def score_line(ev):
    return "%s %s–%s %s" % (ev["home"]["short"], ev["home"]["score"] or 0, ev["away"]["score"] or 0, ev["away"]["short"])


def watch_line(ev):
    names = [s["name"] for s in (ev.get("watch") or {}).get("services", [])]
    return ", ".join(names[:3])


def check_notifications(events, config, notifier, logo_path):
    now = time.time()
    changed = False
    mem = notifier.mem
    for ev in events:
        if not ev.get("fav"):
            continue
        k = ev["id"]
        fav_team = ev["home"] if ev["favSide"] == "home" else ev["away"]
        icon = logo_path(fav_team["id"])
        when = ev["ts"] - now
        if ev["state"] == "pre" and 0 <= when <= config["kickoffLead"] * 60 and k not in mem["kick"]:
            mem["kick"][k] = now
            changed = True
            if config["notifyKickoff"]:
                mins = max(1, int(round(when / 60)))
                watch = watch_line(ev)
                notifier.send("kick-" + k, "%s vs %s in %d min" % (ev["home"]["short"], ev["away"]["short"], mins),
                              ("Watch on " + watch) if watch else LEAGUE_BY_ID[ev["league"]]["name"],
                              icon, ev["url"])
        if ev["state"] in ("in", "post") and ev["home"]["score"] is not None:
            score = "%s-%s" % (ev["home"]["score"], ev["away"]["score"])
            prev = mem["score"].get(k)
            if prev and prev[0] != score:
                try:
                    ph, pa = (int(x) for x in prev[0].split("-"))
                    h, a = int(ev["home"]["score"]), int(ev["away"]["score"])
                except ValueError:
                    ph = pa = h = a = 0
                if (h > ph or a > pa) and config["notifyGoals"]:
                    scorer = ev["home"] if h > ph else ev["away"]
                    goal = next((p for p in reversed(ev["plays"]) if p["goal"] and p["team"] == scorer["id"]), None)
                    who = (" · %s %s" % (goal["player"], goal["minute"])) if goal else ""
                    ours = scorer["id"] == fav_team["id"]
                    notifier.send("goal-" + k, ("GOAL! " if ours else "Goal · ") + scorer["short"],
                                  score_line(ev) + who, logo_path(scorer["id"]), ev["url"])
            if not prev or prev[0] != score:
                mem["score"][k] = [score, now]
                changed = True
        if ev["state"] == "post" and ev["completed"] and k not in mem["final"]:
            mem["final"][k] = now
            changed = True
            if config["notifyFinal"] and now - ev["ts"] < 4 * 3600:
                mine = fav_team["score"] or "0"
                theirs = (ev["away"] if ev["favSide"] == "home" else ev["home"])["score"] or "0"
                verdict = "Win" if int(mine) > int(theirs) else "Loss" if int(mine) < int(theirs) else "Draw"
                notifier.send("final-" + k, "Full time · %s for %s" % (verdict, fav_team["short"]),
                              score_line(ev), icon, ev["url"])
    if changed:
        notifier.save()


# ---------------------------------------------------------------- engine

class Engine:
    def __init__(self, emit=None):
        self.emit = emit
        self.store = Store()
        self.config = dict(DEFAULT_CONFIG, **load_json(CONFIG_FILE, {}))
        self.add_new_leagues()
        self.location = detect_location()
        self.rights = load_rights()
        self.notifier = Notifier()
        self.wake = threading.Event()
        self.errors = {}
        self.last_ok = 0
        self.logos = Logos(self.wake.set) if emit else None

    # ---- config

    def save_config(self):
        save_json(CONFIG_FILE, self.config, indent=2)

    def add_new_leagues(self):
        """Turn on leagues added in an update. Configs from before `leaguesSeen`
        existed knew the original four."""
        seen = self.config.get("leaguesSeen") or ["esp.1", "ita.1", "eng.1", "usa.1"]
        new = [l["id"] for l in LEAGUES if l["id"] not in seen]
        if not new and "leaguesSeen" in self.config:
            return
        self.config["leagues"] = list(self.config["leagues"]) + [l for l in new if l not in self.config["leagues"]]
        self.config["leaguesSeen"] = [l["id"] for l in LEAGUES]
        try:
            self.save_config()
        except OSError:
            pass

    def country(self):
        c = self.config.get("country") or "auto"
        return self.location["country"] if c == "auto" else c

    def enabled(self):
        return [l for l in self.config["leagues"] if l in LEAGUE_BY_ID] or [l["id"] for l in LEAGUES]

    def is_fav(self, league, team_id):
        return any(f["league"] == league and f["id"] == team_id for f in self.config["favorites"])

    # ---- fetching

    def window(self):
        today = local_today()
        return [(off, today + datetime.timedelta(days=off)) for off in range(-DAYS_BACK, DAYS_AHEAD + 1)]

    def hot(self, key, now):
        data = self.store.get(key)
        for e in (data or {}).get("events") or []:
            ev = norm_event(e, "")
            if ev["state"] == "in":
                return True
            if ev["state"] == "pre" and -3600 < ev["ts"] - now < 20 * 60:
                return True
            if ev["state"] == "post" and not ev["completed"]:
                return True
        return False

    def jobs(self):
        now = time.time()
        out = []
        live_leagues = set()
        for league in self.enabled():
            for off, day in self.window():
                key = "sb:%s:%s" % (league, day.strftime("%Y%m%d"))
                if off < -1:
                    ttl = 6 * 3600
                elif off <= 1:
                    hot = self.hot(key, now)
                    if hot:
                        live_leagues.add(league)
                    ttl = 30 if hot else 300
                else:
                    ttl = 1800
                if self.store.age(key) >= ttl:
                    out.append((key, "%s/%s/scoreboard?dates=%s" % (API, league, day.strftime("%Y%m%d"))))
            key = "table:" + league
            if self.store.age(key) >= (600 if league in live_leagues else 3600):
                out.append((key, "%s/%s/standings" % (STANDINGS_API, league)))
            key = "teams:" + league
            if self.store.age(key) >= 86400:
                out.append((key, "%s/%s/teams" % (API, league)))
        for f in self.config["favorites"]:
            for kind, q in (("sched", ""), ("fix", "?fixture=true")):
                key = "%s:%s:%s" % (kind, f["league"], f["id"])
                if self.store.age(key) >= 3 * 3600:
                    out.append((key, "%s/%s/teams/%s/schedule%s" % (API, f["league"], f["id"], q)))
        return out

    def fetch(self, job):
        key, url = job
        try:
            self.store.put(key, http_json(url))
            self.errors.pop(key, None)
            self.last_ok = time.time()
            return True
        except Exception as exc:   # network, HTTP, JSON: retry next round
            self.store.fail(key)
            self.errors[key] = str(exc)
            return False

    def run_jobs(self, pool=None):
        jobs = self.jobs()
        if not jobs:
            return False
        if pool:
            list(pool.map(self.fetch, jobs))
        else:
            with concurrent.futures.ThreadPoolExecutor(8) as p:
                list(p.map(self.fetch, jobs))
        keep = {"sb:%s:%s" % (l, d.strftime("%Y%m%d")) for l in LEAGUE_BY_ID for _, d in self.window()}
        self.store.prune(keep)
        return True

    # ---- snapshot

    def logo(self, team_id, dark=False):
        if not self.logos:
            return ""
        return self.logos.have("team", team_id, dark) or (self.logos.have("team", team_id) if dark else "")

    def logo_path(self, team_id):
        n = self.logo(team_id)
        return os.path.join(LOGO_DIR, n) if n else ""

    def dress(self, team):
        if self.logos:
            self.logos.want("team", team["id"])
        team["logo"] = self.logo(team["id"])
        team["logoDark"] = self.logo(team["id"], True)
        return team

    def all_events(self):
        """Every known event: favorites' schedules, then the day scoreboards on top."""
        events = {}
        for f in self.config["favorites"]:
            for kind in ("sched", "fix"):
                data = self.store.get("%s:%s:%s" % (kind, f["league"], f["id"]))
                for e in (data or {}).get("events") or []:
                    ev = norm_event(e, f["league"])
                    events[ev["id"]] = ev
        for league in self.enabled():
            for _, day in self.window():
                data = self.store.get("sb:%s:%s" % (league, day.strftime("%Y%m%d")))
                for e in (data or {}).get("events") or []:
                    ev = norm_event(e, league)
                    old = events.get(ev["id"])
                    if old and not ev["tv"]:
                        ev["tv"] = old["tv"]
                    events[ev["id"]] = ev
        return sorted(events.values(), key=lambda e: (e["ts"], e["league"], e["home"]["short"]))

    def tables(self):
        out = {}
        for league in LEAGUE_BY_ID:
            data = self.store.get("table:" + league)
            if not data:
                continue
            groups = norm_table(data)
            for g in groups:
                for r in g["rows"]:
                    self.dress(r)
                    r["fav"] = self.is_fav(league, r["id"])
            # Nations League has 14 groups; show the ones you follow first.
            groups.sort(key=lambda g: not any(r["fav"] for r in g["rows"]))
            out[league] = groups
        return out

    def teams(self):
        out = {}
        for league in LEAGUE_BY_ID:
            teams = norm_teams(self.store.get("teams:" + league) or {})
            for t in teams:
                self.dress(t)
                t["fav"] = self.is_fav(league, t["id"])
            out[league] = teams
        return out

    def snapshot(self):
        now = time.time()
        country = self.country()
        events = self.all_events()
        for ev in events:
            self.dress(ev["home"])
            self.dress(ev["away"])
            home_fav = self.is_fav(ev["league"], ev["home"]["id"])
            away_fav = self.is_fav(ev["league"], ev["away"]["id"])
            ev["fav"] = home_fav or away_fav
            ev["favSide"] = "home" if home_fav else "away" if away_fav else ""
            ev["watch"] = where_to_watch(ev, country, self.config, self.rights)

        tables = self.tables()
        teams = self.teams()
        standing = {}
        for league, groups in tables.items():
            for g in groups:
                for r in g["rows"]:
                    standing[(league, r["id"])] = dict(r, group=g["name"])

        favorites = []
        for f in self.config["favorites"]:
            mine = [e for e in events if e["league"] == f["league"] and f["id"] in (e["home"]["id"], e["away"]["id"])]
            live = next((e for e in mine if e["state"] == "in"), None)
            upcoming = [e for e in mine if e["state"] == "pre" and e["ts"] > now - 3 * 3600 and e["status"] != "STATUS_POSTPONED"]
            played = [e for e in mine if e["state"] == "post" and e["completed"]]
            form = []
            for e in played[-5:]:
                us, them = (e["home"], e["away"]) if e["home"]["id"] == f["id"] else (e["away"], e["home"])
                try:
                    a, b = int(us["score"] or 0), int(them["score"] or 0)
                except ValueError:
                    continue
                form.append({"r": "W" if a > b else "L" if a < b else "D", "score": "%d–%d" % (a, b),
                             "vs": them["short"], "home": us is e["home"]})
            info = next((t for t in teams.get(f["league"], []) if t["id"] == f["id"]), None)
            team = self.dress(dict(f, color=(info or {}).get("color", "")))
            favorites.append({
                "team": team,
                "league": f["league"],
                "live": live,
                "next": upcoming[0] if upcoming else None,
                "after": upcoming[1] if len(upcoming) > 1 else None,
                "last": played[-1] if played else None,
                "form": form,
                "standing": standing.get((f["league"], f["id"])),
            })
        # Soonest first: live matches, then by kickoff; teams with nothing
        # scheduled go last. Ties keep the order you followed them in.
        favorites.sort(key=lambda f: (0, f["live"]["ts"]) if f["live"]
                       else (1, f["next"]["ts"]) if f["next"] else (2, 0))

        today = local_today()
        start = datetime.datetime.combine(today - datetime.timedelta(days=DAYS_BACK), datetime.time()).timestamp()
        end = datetime.datetime.combine(today + datetime.timedelta(days=DAYS_AHEAD + 1), datetime.time()).timestamp()
        window = [e for e in events if start <= e["ts"] < end and e["league"] in self.enabled()]

        leagues = []
        for l in LEAGUES:
            if self.logos:
                self.logos.want("league", l["logoId"])
            leagues.append(dict(l, enabled=l["id"] in self.enabled(),
                                logo=self.logos.have("league", l["logoId"]) if self.logos else "",
                                logoDark=(self.logos.have("league", l["logoId"], True) or self.logos.have("league", l["logoId"])) if self.logos else ""))

        countries = [{"value": "auto", "label": "Automatic — %s" % self.auto_label()}]
        for code, c in sorted((self.rights.get("countries") or {}).items(), key=lambda kv: kv[1].get("name", kv[0])):
            countries.append({"value": code, "label": c.get("name", code)})
        if self.config.get("country") not in [c["value"] for c in countries]:
            countries.append({"value": self.config["country"], "label": self.config["country"]})

        known = (self.rights.get("countries") or {}).get(country)
        live_count = sum(1 for e in window if e["state"] == "in")
        status = "ok"
        if not events and self.errors:
            status = "offline"
        elif not events:
            status = "loading"
        elif self.errors and now - self.last_ok > 300:
            status = "stale"

        return {
            "status": status,
            "error": next(iter(self.errors.values()), "") if status in ("offline", "stale") else "",
            "logoDir": LOGO_DIR,
            "country": country,
            "countryName": (known or {}).get("name") or country or "Unknown",
            "countryKnown": bool(known),
            "city": self.location["city"],
            "countries": countries,
            "season": self.rights.get("season", ""),
            "leagues": leagues,
            "favorites": favorites,
            "events": window,
            "liveCount": live_count,
            "tables": tables,
            "teams": teams,
            "config": self.config,
        }, events

    def auto_label(self):
        code = self.location["country"]
        name = ((self.rights.get("countries") or {}).get(code) or {}).get("name") or code or "unknown"
        return "%s, %s" % (self.location["city"], name) if self.location["city"] else name

    # ---- commands

    def follow(self, league, team_id, on=True):
        favs = [f for f in self.config["favorites"] if not (f["league"] == league and f["id"] == team_id)]
        if on:
            info = next((t for t in norm_teams(self.store.get("teams:" + league) or {}) if t["id"] == team_id), None)
            if not info:
                return False
            favs.append({"league": league, "id": team_id, "name": info["name"], "short": info["short"], "abbr": info["abbr"]})
        self.config["favorites"] = favs
        self.save_config()
        return True

    def set_config(self, msg):
        for key, default in DEFAULT_CONFIG.items():
            if key in msg and key != "favorites":
                v = msg[key]
                if isinstance(default, bool):
                    v = bool(v)
                elif isinstance(default, int):
                    v = max(1, min(120, int(v)))
                elif isinstance(default, list):
                    v = [x for x in v if x in LEAGUE_BY_ID] or default
                else:
                    v = str(v)
                self.config[key] = v
        self.save_config()


# ---------------------------------------------------------------- daemon

def daemon():
    lock = threading.Lock()

    def emit(obj):
        with lock:
            try:
                sys.stdout.write(json.dumps(obj, separators=(",", ":")) + "\n")
                sys.stdout.flush()
            except BrokenPipeError:
                os._exit(0)

    engine = Engine(emit)

    def loop():
        last = None
        pool = concurrent.futures.ThreadPoolExecutor(8)
        while True:
            try:
                state, events = engine.snapshot()
                blob = json.dumps(state, sort_keys=True)
                if blob != last:
                    last = blob
                    emit({"type": "state", "state": state})
                engine.run_jobs(pool)
                state, events = engine.snapshot()
                check_notifications(events, engine.config, engine.notifier, engine.logo_path)
                blob = json.dumps(state, sort_keys=True)
                if blob != last:
                    last = blob
                    emit({"type": "state", "state": state})
            except Exception as exc:  # keep the bar alive on an API format change
                emit({"type": "log", "error": "update failed: %r" % exc})
            engine.wake.wait(TICK)
            engine.wake.clear()

    threading.Thread(target=loop, daemon=True).start()

    for line in sys.stdin:
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        cmd, ok, err = msg.get("cmd"), True, None
        if cmd == "refresh":
            engine.rights = load_rights()
            engine.location = detect_location()
            engine.store.expire()
        elif cmd == "follow":
            ok = engine.follow(str(msg.get("league")), str(msg.get("team")), bool(msg.get("on", True)))
            err = None if ok else "team list not loaded yet"
        elif cmd == "config":
            engine.set_config(msg)
        elif cmd == "open":
            ok = open_url(str(msg.get("url") or ""))
            err = None if ok else "no browser launcher found"
        elif cmd == "test":
            engine.notifier.send("test", "GOAL! Matchday", "Notifications are working · 90'+3'",
                                 os.path.join(ASSETS, "ball.svg"))
        else:
            ok, err = False, "unknown command"
        engine.wake.set()
        emit({"type": "result", "id": msg.get("id"), "cmd": cmd, "ok": ok, "error": err})


# ---------------------------------------------------------------- CLI

def fmt_when(ev):
    t = datetime.datetime.fromtimestamp(ev["ts"])
    day = t.date()
    today = local_today()
    if day == today:
        label = "Today"
    elif day == today + datetime.timedelta(days=1):
        label = "Tomorrow"
    else:
        label = t.strftime("%a %b %-d")
    return "%s %s" % (label, t.strftime("%-I:%M %p"))


def describe(ev):
    if ev["state"] == "in":
        return "LIVE %s  %s" % (ev["clock"] or ev["detail"], score_line(ev))
    if ev["state"] == "post":
        return "%s  %s" % (ev["detail"] or "FT", score_line(ev))
    return "%s  %s vs %s" % (fmt_when(ev), ev["home"]["short"], ev["away"]["short"])


def cli_state():
    engine = Engine()
    engine.run_jobs()
    return engine.snapshot()[0]


def print_status(state):
    print("Location: %s%s" % (state["countryName"], "" if state["countryKnown"] else " (no rights data, showing ESPN/global listings)"))
    if not state["favorites"]:
        print("No favorite teams yet. Follow some from the bar panel.")
    for f in state["favorites"]:
        lg = LEAGUE_BY_ID[f["league"]]["short"]
        st = f["standing"]
        rank = ("  #%s · %s pts" % (st["rank"], st["pts"])) if st else ""
        print("\n%s (%s)%s  %s" % (f["team"]["name"], lg, rank, "".join(x["r"] for x in f["form"])))
        ev = f["live"] or f["next"]
        if ev:
            print("  " + describe(ev))
            w = ev["watch"]
            if w["services"]:
                tag = "" if w["source"] == "espn" else " (league rights)"
                print("  Watch: %s%s" % (", ".join(s["name"] for s in w["services"]), tag))
        if f["last"]:
            print("  Last: " + describe(f["last"]))
    today = [e for e in state["events"] if datetime.datetime.fromtimestamp(e["ts"]).date() == local_today()]
    if today:
        print("\nToday")
        for e in today:
            print("  %-8s %s" % (LEAGUE_BY_ID[e["league"]]["short"], describe(e)))


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "status"
    if cmd == "daemon":
        daemon()
    elif cmd == "status":
        state = cli_state()
        if "--json" in argv:
            print(json.dumps(state, indent=2))
        else:
            print_status(state)
    elif cmd == "next":
        state = cli_state()
        evs = [f["live"] or f["next"] for f in state["favorites"] if f["live"] or f["next"]]
        evs.sort(key=lambda e: (e["state"] != "in", e["ts"]))
        print(describe(evs[0]) if evs else "No upcoming matches for your teams.")
    else:
        print(__doc__.strip())
        return 0 if cmd in ("-h", "--help", "help") else 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv) or 0)
