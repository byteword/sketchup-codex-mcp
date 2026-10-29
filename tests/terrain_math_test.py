"""Exercise actual terrain JS in Jint; independent geometric/numeric expectations."""
import json
from pathlib import Path
import subprocess
import sys
import unittest

EXE=sys.argv.pop(1)
FOLDER=Path(__file__).resolve().parents[1]/'docs/library-spec/example/terrain-grid'
class TerrainMathTest(unittest.TestCase):
    def script(self, **params):
        package=dict(source=(FOLDER/'technique.js').read_text(encoding='utf-8'),schema=json.loads((FOLDER/'inputs.schema.json').read_text()),dependencies={},helpers={})
        request=dict(root='terrain',packages=dict(terrain=package),input=dict(params=params,inputs={}),timeout_ms=1000,memory_mib=64)
        r=subprocess.run([EXE,'--library-worker'],input=json.dumps(request).encode(),capture_output=True,timeout=8)
        self.assertEqual(0,r.returncode,r.stderr)
        return json.loads(r.stdout)
    def mesh(self, **params):
        r=self.script(**params);self.assertTrue(r['ok'],r)
        return r['result']['steps'][0]['arguments']
    def test_flat_raw_default_upward_triangle_winding(self):
        args=self.mesh();self.assertEqual('auto',args['grouping']);o=args['options']
        self.assertEqual(81,len(o['points_mm']));self.assertEqual(128,len(o['triangles']))
        edges={}
        for t in o['triangles']:
            a,b,c=[o['points_mm'][i] for i in t]
            self.assertGreater((b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]),0)
            self.assertTrue(all(v[2]==0 for v in (a,b,c)))
            for x,y in zip(t,t[1:]+t[:1]):edges.setdefault(tuple(sorted((x,y))),[]).append((x,y))
        for edge in edges.values():
            self.assertLessEqual(len(edge),2)
            if len(edge)==2:self.assertEqual(edge[0],edge[1][::-1])
    def test_height_order_origin_and_material(self):
        args=self.mesh(columns=1,rows=1,width_mm=100,depth_mm=200,heights_mm=[10,20,30,40],origin_mm=[500,600,700],material='Ground',grouping='group')
        self.assertEqual([[500,600,710],[600,600,720],[500,800,730],[600,800,740]],args['options']['points_mm'])
        self.assertEqual('Ground',args['options']['material']);self.assertEqual('group',args['grouping'])
    def test_idw_exact_sample_and_symmetric_midpoint(self):
        points=self.mesh(columns=2,rows=1,width_mm=100,depth_mm=100,samples_mm=[[0,0,10],[100,0,90]])['options']['points_mm']
        self.assertAlmostEqual(10,points[0][2]);self.assertAlmostEqual(50,points[1][2]);self.assertAlmostEqual(90,points[2][2])
        self.assertAlmostEqual(50,points[4][2])
    def test_bump_center_half_radius_boundary_and_outside(self):
        points=self.mesh(columns=4,rows=1,width_mm=200,depth_mm=100,bumps=[dict(center_mm=[0,0],radius_mm=100,height_mm=80)])['options']['points_mm']
        self.assertEqual([80,40,0,0,0],[p[2] for p in points[:5]])
        self.assertTrue(all(p[2]==0 for p in points[5:]))
    def test_reject_ambiguous_samples_heights_and_overbudget(self):
        for params in [dict(columns=12,rows=12),dict(heights_mm=[0]),dict(samples_mm=[[1,2,3],[1,2,4]]),dict(columns=1,rows=1,heights_mm=[0,0,0,0],samples_mm=[[0,0,0]])]:
            r=self.script(**params);self.assertFalse(r['ok'],r);self.assertEqual('input_invalid',r['error']['code'])
    def test_maximum_cells_fits_native_plan_budget(self):
        args=self.mesh(columns=8,rows=12);self.assertEqual(192,len(args['options']['triangles']))
        self.assertLess(len(json.dumps(args)),40000)

if __name__=='__main__':unittest.main(verbosity=2)
