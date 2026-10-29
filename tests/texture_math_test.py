"""Numeric acceptance of the actual bundled script in the embedded Jint worker."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import unittest

EXE = sys.argv.pop(1)
ROOT = Path(__file__).resolve().parents[1]
FOLDER = ROOT / 'docs/library-spec/example/face-texture'

class TextureMathTest(unittest.TestCase):
    def run_script(self, params, snapshot=None):
        case = json.loads((FOLDER/'tests.json').read_text(encoding='utf-8'))['cases'][0]
        inputs = copy.deepcopy(case['inputs'])
        if snapshot:
            inputs['face']['target'] = snapshot
        package = dict(source=(FOLDER/'technique.js').read_text(encoding='utf-8'),
                       schema=json.loads((FOLDER/'inputs.schema.json').read_text(encoding='utf-8')),
                       dependencies={}, helpers={})
        request = dict(root='texture',packages=dict(texture=package),input=dict(params=params,inputs=inputs),timeout_ms=1000,memory_mib=64)
        result=subprocess.run([EXE,'--library-worker'],input=json.dumps(request).encode(),capture_output=True,timeout=8)
        self.assertEqual(0,result.returncode,result.stderr)
        return json.loads(result.stdout)

    def mapping(self, params, snapshot=None):
        r=self.run_script(params,snapshot)
        self.assertTrue(r['ok'],r)
        return r['result']['steps'][0]['arguments']['mapping']

    def assert_point(self, expected, actual):
        for a,b in zip(expected,actual):self.assertAlmostEqual(a,b,places=6)

    def test_rotation_offset_and_existing_projective_uv_preserved(self):
        result=self.mapping(dict(rotation_degrees=90,offset_mm=[50,25]))
        self.assert_point([50,1025,0],result[1]['point_mm'])
        self.assert_point([-450,1025,0],result[2]['point_mm'])
        self.assertEqual([2,2],result[2]['uv'])

    def test_tile_mm_independent_from_image_pixels(self):
        result=self.mapping(dict(mode='tile',tile_size_mm=[300,600]))
        self.assert_point([300,600,0],result[2]['point_mm'])
        self.assertEqual([1,1],result[2]['uv'])

    def test_fit_and_back_clear(self):
        result=self.mapping(dict(mode='fit'))
        self.assert_point([1000,500,0],result[2]['point_mm'])
        self.assertEqual([1,1],result[2]['uv'])
        result=self.run_script(dict(mode='clear',side='back'))
        args=result['result']['steps'][0]['arguments']
        self.assertFalse(args['front']);self.assertEqual('clear',args['action']);self.assertNotIn('mapping',args)

    def test_scale_mirror_shear_pivot(self):
        result=self.mapping(dict(scale=[2,1],flip_u=True,pivot_fraction=[.5,.5],shear_degrees=45))
        self.assert_point([1250,0,0],result[0]['point_mm'])
        self.assert_point([-250,500,0],result[2]['point_mm'])

    def test_tilt_uses_projective_divisor(self):
        result=self.mapping(dict(tilt=[.5,0]))
        self.assert_point([1000/1.5,500/1.5,0],result[2]['point_mm'])
        bad=self.run_script(dict(scale=[10,10],tilt=[-.9,0]))
        self.assertFalse(bad['ok']);self.assertEqual('input_invalid',bad['error']['code'])

    def test_tilted_world_face_keeps_geometry_plane(self):
        sample=json.loads((FOLDER/'tests.json').read_text(encoding='utf-8'))['cases'][0]['inputs']['face']['target']
        sample['frame'].update(origin_mm=[2000,100,400],u=[0,1,0],v=[0,0,1],normal=[1,0,0])
        result=self.mapping(dict(mode='tile',tile_size_mm=[300,600]),sample)
        self.assert_point([2000,400,1000],result[2]['point_mm'])
        self.assertTrue(all(point['point_mm'][0]==2000 for point in result))

    def test_folded_pins_rejected_and_no_direct_texture_relative_rejected(self):
        bad=self.run_script(dict(corner_offsets_mm=[[0,0],[-1000,0],[0,0],[0,0]]))
        self.assertFalse(bad['ok'])
        sample=json.loads((FOLDER/'tests.json').read_text(encoding='utf-8'))['cases'][0]['inputs']['face']['target']
        sample['sides']['front']['uv']=None
        self.assertFalse(self.run_script(dict(mode='transform'),sample)['ok'])
        self.assertTrue(self.run_script(dict(mode='fit',material='wood'),sample)['ok'])

if __name__=='__main__':unittest.main(verbosity=2)
