"""Optional independent DXF reader acceptance. Dev-only: ezdxf1.4.4, no runtime dependency."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import ezdxf

root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='probe-dxf-') as folder:
    subprocess.run([*sys.argv[1:],str(root/'tests/export_dxf_fixture.rb'),folder],cwd=root,check=True)
    reports=[]
    vertices=[(500,600,700),(1500,600,1700),(1500,2600,1200)]
    for plane,axes in [('XY',(0,1)),('XZ',(0,2)),('YZ',(1,2))]:
        doc=ezdxf.readfile(Path(folder)/(plane+'.dxf'))
        assert doc.dxfversion=='AC1015' and doc.units==4
        lines=list(doc.modelspace().query('LINE'));assert len(lines)==3
        actual=set()
        for line in lines:
            a,b=line.dxf.start,line.dxf.end
            assert a.z==b.z==0
            actual.add(tuple(sorted(((round(a.x,5),round(a.y,5)),(round(b.x,5),round(b.y,5))))))
        points=[tuple(v[i] for i in axes) for v in vertices]
        expected={tuple(sorted((points[i],points[(i+1)%3]))) for i in range(3)}
        assert actual==expected,(actual,expected)
        auditor=doc.audit();assert not auditor.errors,[str(e) for e in auditor.errors]
        reports.append(dict(plane=plane,lines=3,units='mm',coordinates_match=True,audit_errors=len(auditor.errors),audit_fixes=len(auditor.fixes)))
    report=dict(reader='ezdxf',version=ezdxf.__version__,results=reports,native_sketchup=False)
    (root/'docs/validation-0.12.0-dxf.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(report))
