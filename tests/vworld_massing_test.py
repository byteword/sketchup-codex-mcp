import json,sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent.parent/'scripts'))
from vworld_massing_geometry import triangles,signed_area,triangle_intersection_area,match_footprints,align_site

class GeometryTests(unittest.TestCase):
    def test_concave_triangulation(self):
        p=[[0,0],[4000,0],[4000,1000],[1000,1000],[1000,4000],[0,4000]]
        self.assertAlmostEqual(sum(abs(signed_area(t)) for t in triangles(p)),7000000)
    def test_overlap_exact(self):
        a=[[0,0],[4000,0],[4000,4000],[0,4000]];b=[[2000,2000],[6000,2000],[6000,6000],[2000,6000]]
        self.assertAlmostEqual(sum(triangle_intersection_area(x,y) for x in triangles(a) for y in triangles(b)),4000000)
    def test_disjoint(self):
        a=[[0,0],[1000,0],[0,1000]];b=[[2000,0],[3000,0],[2000,1000]]
        self.assertEqual(triangle_intersection_area(a,b),0)
    def fixture(self,height=10):
        a=dict(lon0=0,lat0=0,origin_mm=[0,0],mm_per_lon_degree=1000,mm_per_lat_degree=1000)
        ring=[[0,0,0],[1000,0,0],[1000,1000,0],[0,1000,0]]
        f=dict(path=['1','2'],loops=[ring],distance_mm=10)
        feature=dict(geometry=dict(type='Polygon',coordinates=[[[0,0],[1,0],[1,1],[0,1],[0,0]]]),properties=dict(height_m=height,height_mm=height*1000 if height else None,pnu='1130510300100530025',building_id='a',source_updated_at='2026-10-30'))
        return a,f,feature
    def test_matching_preserves_original(self):
        a,f,g=self.fixture();matched,skipped=match_footprints([f],[g],a)
        self.assertEqual(len(matched),1);self.assertEqual(skipped,[])
        self.assertEqual(matched[0]['ring_mm'],f['loops'][0]);self.assertEqual(matched[0]['height_mm'],10000)
        self.assertAlmostEqual(matched[0]['iou'],1)
    def test_missing_height_is_not_estimated(self):
        a,f,g=self.fixture(None);m,s=match_footprints([f],[g],a)
        self.assertEqual(m,[]);self.assertEqual(s[0]['reason'],'height_unavailable')
    def test_duplicate_correspondence_is_not_reused(self):
        a,f,g=self.fixture();f2=dict(f,path=['1','3']);m,s=match_footprints([f,f2],[g],a)
        self.assertEqual(m,[]);self.assertEqual(len(s),2)
    def test_holes_subtract_intersection(self):
        a,f,g=self.fixture();g['geometry']['coordinates'].append([[.25,.25],[.75,.25],[.75,.75],[.25,.75],[.25,.25]])
        m,s=match_footprints([f],[g],a);self.assertAlmostEqual(m[0]['coverage'],.75)
    def test_site_scale_mismatch_rejected(self):
        with self.assertRaises(ValueError):align_site([[0,100000,0],[-100000,0,0],[0,-100000,0],[100000,0,0]],[[127,37.0001],[126.9999,37],[127,36.9999],[127.0001,37]])

if __name__=='__main__':unittest.main(verbosity=2)
