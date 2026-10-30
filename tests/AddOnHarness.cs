using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using SketchUpPipeProbe;

class AddOnHarness
{
    static int count;
    static Dictionary<string,object> previewData;
    static void Check(bool ok,string name){if(!ok)throw new Exception("FAILED: "+name);count++;Console.WriteLine("PASS "+name);}
    static async Task Reject(Func<Task<object>> work,string name){bool rejected=false;try{await work();}catch{rejected=true;}Check(rejected,name);}
    [STAThread]
    static int Main(string[] args) {
        if(LibraryWorker.TryMain(args))return 0;
        string root=Path.Combine(Path.GetTempPath(),"probe-addons-test-"+Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(Path.Combine(root,"AddOns","vworld"));
        try {
            foreach(string f in new[]{"addon.json","addon.js","terrain.html"})File.Copy(Path.Combine(args[0],"AddOns","vworld",f),Path.Combine(root,"AddOns","vworld",f));
            Run(root).GetAwaiter().GetResult();
            using(var preview=new GeoJsonView()){preview.Size=new System.Drawing.Size(600,400);preview.SetData(previewData);using(var bmp=new System.Drawing.Bitmap(600,400))preview.DrawToBitmap(bmp,new System.Drawing.Rectangle(0,0,600,400));Check(true,"polygon preview renders");}
            // Construct and switch real WinForms controls without showing a user window.
            using(var form=new AddOnForm(new AddOnService(Path.Combine(root,"AddOns"),Path.Combine(root,"settings")))) {
                var m=typeof(AddOnForm).GetMethod("ShowPackage",System.Reflection.BindingFlags.NonPublic|System.Reflection.BindingFlags.Instance);
                m.Invoke(form,null);m.Invoke(form,null);
                var ops=(ComboBox)typeof(AddOnForm).GetField("operation",System.Reflection.BindingFlags.NonPublic|System.Reflection.BindingFlags.Instance).GetValue(form);
                Check(ops.Items.Count==3,"all operation controls available");
                for(int i=0;i<ops.Items.Count;i++)ops.SelectedIndex=i;
                Check(!form.IsDisposed,"settings controls can reload repeatedly");
            }
            Console.WriteLine("Add-on tests: "+count+" passed");return 0;
        }catch(Exception e){Console.Error.WriteLine(e);return 1;}
        finally{Directory.Delete(root,true);}
    }
    static async Task Run(string root) {
        var svc=new AddOnService(Path.Combine(root,"AddOns"),Path.Combine(root,"settings"));
        var p=svc.Load("vworld");
        Check(svc.List().Length==1,"source discovery");
        Check(!Lib.Bool(Lib.Obj(svc.List()[0]),"enabled"),"disabled by default");
        var input=Lib.Map("pnu","1174011000102450001");
        var denied=Lib.Obj(await svc.QueryAsync("vworld",input,CancellationToken.None));
        Check(!Lib.Bool(denied,"ok"),"disabled query denied");
        var prepared=Lib.Obj(await AddOnService.Script(p,"prepare",input,CancellationToken.None));
        var q=Lib.Obj(prepared["query"]);
        Check(Lib.Str(q,"typename")=="dt_d010" && Lib.Str(q,"output")=="application/json","official endpoint parameters");
        Check(!q.ContainsKey("key"),"source cannot see API key");
        Check(AddOnService.ResolveEndpoint(p,prepared).EndsWith("getBldgisSpceWFS"),"building endpoint alias");
        bool undeclared=false;try{AddOnService.ResolveEndpoint(p,Lib.Map("endpoint","https://evil.example/x"));}catch{undeclared=true;}Check(undeclared,"source cannot choose undeclared endpoint");
        var parcelReq=Lib.Obj(await AddOnService.Script(p,"prepare",Lib.Map("operation","parcels","point","127.17,37.56"),CancellationToken.None));
        Check(AddOnService.ResolveEndpoint(p,parcelReq).EndsWith("getCtnlgsSpceWFS") && Lib.Str(Lib.Obj(parcelReq["query"]),"typename")=="dt_d002","parcel official endpoint and layer");
        Check(Lib.Str(Lib.Obj(parcelReq["query"]),"bbox").EndsWith("EPSG:4326"),"point converted to neighborhood bbox");
        string parcelBody="{\"type\":\"FeatureCollection\",\"features\":[{\"type\":\"Feature\",\"id\":\"p1\",\"properties\":{\"pnu\":\"1174011000102450001\",\"lnm_lndcgr_smbol\":\"245 대\"},\"geometry\":{\"type\":\"Polygon\",\"coordinates\":[[[127,37],[127.001,37],[127.001,37.001],[127,37]],[[127.0002,37.0002],[127.0003,37.0002],[127.0003,37.0003],[127.0002,37.0002]]]}}]}";
        var parcelData=Lib.Obj(await AddOnService.Script(p,"parse",Lib.Map("body",parcelBody,"request",parcelReq),CancellationToken.None));
        var gj=Lib.Obj(parcelData["geojson"]);var geom=Lib.Obj(Lib.Obj(((object[])gj["features"])[0])["geometry"]);
        Check(((object[])geom["coordinates"]).Length==2,"parcel holes preserved");
        Check(Lib.Str(Lib.Obj(((object[])parcelData["parcels"])[0]),"parcel_label")=="245 대","parcel label mapped");
        previewData=gj;
        await Reject(()=>AddOnService.Script(p,"parse",Lib.Map("body",parcelBody.Replace("[127,37]]","[127,38]]"),"request",parcelReq),CancellationToken.None),"unclosed polygon rejected");
        var addrReq=Lib.Obj(await AddOnService.Script(p,"prepare",Lib.Map("operation","address","address","서울특별시 중구 세종대로 110"),CancellationToken.None));
        Check(AddOnService.ResolveEndpoint(p,addrReq)=="https://api.vworld.kr/req/address","geocoding endpoint");
        var addrData=Lib.Obj(await AddOnService.Script(p,"parse",Lib.Map("body","{\"response\":{\"status\":\"OK\",\"result\":{\"point\":{\"x\":\"126.978\",\"y\":\"37.5665\"}}}}","request",addrReq),CancellationToken.None));
        Check(Lib.Str(Lib.Obj(addrData["followup"]),"operation")=="parcels","address followup uses parcel neighborhood");
        var noAddress=Lib.Obj(await AddOnService.Script(p,"parse",Lib.Map("body","{\"response\":{\"status\":\"NOT_FOUND\"}}","request",addrReq),CancellationToken.None));
        Check(Lib.Str(noAddress,"status")=="error","missing address does not become zero coordinate");
        var badAddress=Lib.Obj(await AddOnService.Script(p,"parse",Lib.Map("body","{\"response\":{\"status\":\"OK\",\"result\":{\"point\":{\"x\":null,\"y\":\"\"}}}}","request",addrReq),CancellationToken.None));
        Check(Lib.Str(badAddress,"status")=="error","blank or null address coordinates do not become zero");
        var bbox=Lib.Obj(await AddOnService.Script(p,"prepare",Lib.Map("bbox","127.17,37.56,127.18,37.57"),CancellationToken.None));
        Check(Lib.Str(Lib.Obj(bbox["query"]),"bbox")=="37.56,127.17,37.57,127.18,EPSG:4326","official latitude-first BBOX");
        foreach(var bad in new[]{Lib.Map(),Lib.Map("pnu","123"),Lib.Map("pnu",input["pnu"],"bbox","1,2,3,4"),
            Lib.Map("bbox","127,37,128,38"),Lib.Map("bbox","127,37,,38"),Lib.Map("pnu",input["pnu"],"limit",101),
            Lib.Map("pnu",input["pnu"],"api_key","forbidden"),Lib.Map("pnu",1234567890123456789L),Lib.Map("pnu",input["pnu"],"limit",0)})
            await Reject(()=>AddOnService.Script(p,"prepare",bad,CancellationToken.None),"invalid input "+Lib.Json(bad));
        object[] raw={"12.5",0,null,"","-1","oops",true};
        var features=raw.Select((hg,i)=>(object)Lib.Map("id","building."+i,"properties",Lib.Map("hg",hg,"pnu",input["pnu"],"gis_idntfc_no","x","last_updt_dt","2026-01-01"))).ToArray();
        string response=Lib.Json(Lib.Map("type","FeatureCollection","features",features));
        var parsed=Lib.Obj(await AddOnService.Script(p,"parse",Lib.Map("body",response,"request",prepared),CancellationToken.None));
        var rows=(object[])parsed["buildings"];
        Check(Convert.ToDouble(Lib.Obj(rows[0])["height_mm"])==12500,"height m to mm");
        Check(rows.Skip(1).All(r=>Lib.Obj(r)["height_m"]==null),"zero missing negative malformed heights are not guessed");
        Check(Lib.Str(Lib.Obj(rows[1]),"height_status")=="zero_unavailable","zero retains unavailable distinction");
        Check(Lib.Str(Lib.Obj(rows[0]),"source_height_raw")=="12.5","raw source height preserved");
        var limited=Lib.Obj(await AddOnService.Script(p,"parse",Lib.Map("body",response,"request",Lib.Map("limit",7)),CancellationToken.None));
        Check(Lib.Bool(limited,"possibly_truncated"),"full page marked incomplete");
        foreach(string error in new[]{"<ExceptionReport>bad key</ExceptionReport>","{\"error\":\"bad key\"}","null"}) {
            var e=Lib.Obj(await AddOnService.Script(p,"parse",Lib.Map("body",error,"request",prepared),CancellationToken.None));
            Check(Lib.Str(e,"status")=="error","HTTP 200 error body rejected");
        }
        const string key="test-secret-한글-123";
        svc.SaveSettings(p,true,new Dictionary<string,string>{{"api_key",key},{"domain","https://example.org"}},new HashSet<string>());
        string disk=File.ReadAllText(Path.Combine(root,"settings","vworld.json"));
        Check(!disk.Contains(key) && !disk.Contains("test-secret"),"DPAPI storage contains no plaintext key");
        Check(Lib.Bool(Lib.Obj(svc.List()[0]),"enabled") && !Lib.Json(svc.List()).Contains("secrets"),"listing exposes status only");
        string viewer=svc.PrepareViewer("vworld");
        Check(File.ReadAllText(viewer)==p.ViewerSource && !File.ReadAllText(viewer).Contains(key),"viewer snapshot contains source and no credential");
        bool received=false;
        svc.Fetch=(uri,ct)=>{received=uri.AbsoluteUri.Contains(Uri.EscapeDataString(key)) && uri.AbsolutePath=="/ned/wfs/getBldgisSpceWFS";return Task.FromResult(response);};
        var result=Lib.Obj(await svc.QueryAsync("vworld",input,CancellationToken.None));
        Check(Lib.Bool(result,"ok") && received,"host decrypts key only for HTTPS request");
        string sourcePath=Path.Combine(root,"AddOns","vworld","addon.js"),originalSource=File.ReadAllText(sourcePath);
        File.AppendAllText(sourcePath,"\nvar originalParse=parse;parse=function(x){if(x.request.query.key || x.request.query.domain)throw new Error('Credential reached worker');return originalParse(x);};");
        p=svc.Load("vworld");svc.SaveSettings(p,true,new Dictionary<string,string>(),new HashSet<string>());
        result=Lib.Obj(await svc.QueryAsync("vworld",input,CancellationToken.None));Check(Lib.Bool(result,"ok"),"parse worker never receives injected credentials");
        File.WriteAllText(sourcePath,originalSource);p=svc.Load("vworld");svc.SaveSettings(p,true,new Dictionary<string,string>(),new HashSet<string>());
        svc.Fetch=(uri,ct)=>{received=uri.AbsolutePath=="/ned/wfs/getCtnlgsSpceWFS";return Task.FromResult(parcelBody);};
        result=Lib.Obj(await svc.QueryAsync("vworld",Lib.Map("operation","parcels","point","127,37"),CancellationToken.None));Check(Lib.Bool(result,"ok")&&received,"parcel request routes through credential host");
        svc.Fetch=(uri,ct)=>{received=uri.AbsolutePath=="/ned/wfs/getBldgisSpceWFS";return Task.FromResult(response);};
        svc.SaveSettings(p,true,new Dictionary<string,string>{{"api_key",""},{"domain","https://example.org"}},new HashSet<string>());
        await svc.QueryAsync("vworld",input,CancellationToken.None);Check(received,"blank key preserves credential");
        svc.Fetch=(uri,ct)=>{throw new System.Net.WebException(uri.AbsoluteUri);};
        result=Lib.Obj(await svc.QueryAsync("vworld",input,CancellationToken.None));
        Check(!Lib.Bool(result,"ok") && !Lib.Json(result).Contains("test-secret"),"URL-bearing network errors do not leak keys");
        svc.Fetch=(uri,ct)=>Task.FromResult(response.Replace("building.0",key));
        result=Lib.Obj(await svc.QueryAsync("vworld",input,CancellationToken.None));
        Check(!Lib.Json(result).Contains("test-secret"),"reflected credential redacted before parser");
        svc.Fetch=(uri,ct)=>Task.FromResult("{\"error\":\"bad key\"}");
        result=Lib.Obj(await svc.QueryAsync("vworld",input,CancellationToken.None));
        Check(!Lib.Bool(result,"ok"),"service error sets outer failure");
        await Reject(()=>AddOnService.Script(p,"parse",Lib.Map("body",response.Replace("1174011000102450001","1174011000102450002"),"request",prepared),CancellationToken.None),"mismatched response PNU rejected");
        svc.Fetch=async (uri,ct)=>{await Task.Delay(5000,ct);return response;};
        using(var stop=new CancellationTokenSource(100)) {
            result=Lib.Obj(await svc.QueryAsync("vworld",input,stop.Token));
            Check(!Lib.Bool(result,"ok"),"cancellation terminates query");
        }
        string viewerPath=Path.Combine(root,"AddOns","vworld","terrain.html");File.AppendAllText(viewerPath,"\n<!--changed-->");
        Check(!Lib.Bool(Lib.Obj(svc.List()[0]),"enabled"),"changed viewer requires local activation");
        bool viewerDenied=false;try{svc.PrepareViewer("vworld");}catch{viewerDenied=true;}Check(viewerDenied,"unapproved viewer not launched");
        File.WriteAllText(viewerPath,p.ViewerSource);
        File.AppendAllText(Path.Combine(root,"AddOns","vworld","addon.js"),"\n// changed\n");
        Check(!Lib.Bool(Lib.Obj(svc.List()[0]),"enabled"),"changed source requires local activation");
        result=Lib.Obj(await svc.QueryAsync("vworld",input,CancellationToken.None));Check(!Lib.Bool(result,"ok"),"changed source denied before HTTP");
        bool stale=false;try{svc.SaveSettings(p,true,new Dictionary<string,string>(),new HashSet<string>());}catch{stale=true;}Check(stale,"stale settings dialog cannot approve changed code");
        p=svc.Load("vworld");svc.SaveSettings(p,false,new Dictionary<string,string>(),new HashSet<string>{"api_key"});
        Check(Lib.Str(Lib.Obj(svc.ReadSettings("vworld")["secrets"]),"api_key")=="","credential delete");
        bool traversal=false;try{svc.Load("../vworld");}catch{traversal=true;}Check(traversal,"path traversal denied");
        Check(AddOnCatalog.List().Length==2,"generic MCP tool catalog");
        AddOnCatalog.Validate("sketchup_addon_query",Lib.Map("addon_id","vworld","inputs",input));
        bool secretArg=false;try{AddOnCatalog.Validate("sketchup_addon_query",Lib.Map("addon_id","vworld","inputs",input,"key","bad"));}catch{secretArg=true;}Check(secretArg,"MCP secret argument rejected");
        var endless=new AddOnPackage {Source="function prepare(x){while(true){}}"};
        await Reject(()=>AddOnService.Script(endless,"prepare",Lib.Map(),CancellationToken.None),"script execution budget");
        var clr=new AddOnPackage {Source="function prepare(x){return {x:System.IO.File.ReadAllText('x')};}"};
        await Reject(()=>AddOnService.Script(clr,"prepare",Lib.Map(),CancellationToken.None),"no CLR IO in source");
    }
}
