import importlib.util
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('matchday', Path(__file__).parents[1] / 'lib/matchday.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class ChampionsLeagueTests(unittest.TestCase):
    def test_upgrade_enables_champions_without_restoring_disabled_leagues(self):
        engine = m.Engine.__new__(m.Engine)
        engine.config = {'leagues': ['esp.1'], 'leaguesSeen': ['esp.1', 'ita.1', 'eng.1', 'usa.1', 'uefa.nations'],
                         'favorites': [{'league': 'esp.1', 'id': '83'}]}
        with patch.object(engine, 'save_config') as save:
            engine.add_new_leagues()
            self.assertEqual(engine.config['leagues'], ['esp.1', 'uefa.champions'])
            self.assertEqual(engine.config['favorites'], [{'league': 'esp.1', 'id': '83'}])
            save.assert_called_once()
            engine.add_new_leagues()
            save.assert_called_once()

    def test_champions_fetch_jobs_include_fixtures_table_and_team_catalog(self):
        engine = m.Engine.__new__(m.Engine)
        engine.config = {'leagues': ['uefa.champions'], 'favorites': [{'league': 'uefa.champions', 'id': '83'}]}
        class EmptyStore:
            def age(self, key): return float('inf')
            def get(self, key): return None
        engine.store = EmptyStore()
        jobs = dict(engine.jobs())
        self.assertIn('table:uefa.champions', jobs)
        self.assertIn('teams:uefa.champions', jobs)
        self.assertTrue(any('/uefa.champions/scoreboard?' in url for url in jobs.values()))
        self.assertTrue(jobs['fix:uefa.champions:83'].endswith('/teams/83/schedule?fixture=true'))

    def test_broadcasters_cover_supported_countries_and_match_listings_take_priority(self):
        with patch.object(m, 'USER_DIR', '/nonexistent/matchday-test'):
            rights = m.load_rights()
        event = {'league': 'uefa.champions', 'tv': [], 'home': {'abbr': 'BAR'}, 'away': {'abbr': 'ARS'}}
        for country in ['US', 'CA', 'MX', 'GB', 'IE', 'ES', 'IT']:
            watch = m.where_to_watch(event, country, {'spanish': True}, rights)
            self.assertTrue(watch['services'], country)
            self.assertTrue(all(s['url'] for s in watch['services']), country)
            self.assertNotIn('bbc', [s['id'] for s in watch['services']])
        event['tv'] = ['Paramount+']
        watch = m.where_to_watch(event, 'US', {'spanish': True}, rights)
        self.assertEqual(watch['source'], 'espn')
        self.assertEqual([s['id'] for s in watch['services']], ['paramount'])
        self.assertNotIn('serie-a', watch['services'][0]['url'])


if __name__ == '__main__':
    unittest.main()
