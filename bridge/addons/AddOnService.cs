using System;
using System.IO;
using System.Linq;
using System.Net;
using System.Text;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Threading;
using System.Threading.Tasks;
using System.Runtime.InteropServices;

namespace SketchUpPipeProbe
{
    public sealed class AddOnPackage
    {
        public string Id,Source,Hash,ViewerSource;
        public Dictionary<string,object> Manifest;
        public override string ToString(){return Lib.Str(Manifest,"name")+" ("+Id+")";}
    }
    public sealed class AddOnService
    {
        public readonly string Root,SettingsRoot;
        readonly object settingsLock=new object();
        readonly SemaphoreSlim gate=new SemaphoreSlim(2,2);
        internal Func<Uri,CancellationToken,Task<string>> Fetch=Download;
        public AddOnService():this(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"AddOns"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"SketchUpCodexMcp","AddOns")){}
        public AddOnService(string root,string settingsRoot){Root=Path.GetFullPath(root);SettingsRoot=Path.GetFullPath(settingsRoot);}
        [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]
        struct FindData {
            public uint Attributes;
            public System.Runtime.InteropServices.ComTypes.FILETIME Creation,Access,Write;
            public uint SizeHigh,SizeLow,Tag,Reserved;
            [MarshalAs(UnmanagedType.ByValTStr,SizeConst=260)]public string Name;
            [MarshalAs(UnmanagedType.ByValTStr,SizeConst=14)]public string Alternate;
        }
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
        static extern IntPtr FindFirstFile(string path,out FindData data);
        [DllImport("kernel32.dll")]
        static extern bool FindClose(IntPtr handle);
        static bool RedirectsName(string path) {
            if((File.GetAttributes(path)&FileAttributes.ReparsePoint)==0)return false;
            FindData data;IntPtr handle=FindFirstFile(path.TrimEnd(Path.DirectorySeparatorChar),out data);
            if(handle==new IntPtr(-1))throw new IOException("Cannot inspect add-on path");
            try{return (data.Tag&0x20000000)!=0;}finally{FindClose(handle);}
        }
        static void PlainPath(string path) {
            for(var d=new DirectoryInfo(Path.GetDirectoryName(path));d!=null;d=d.Parent)
                if(d.Exists && RedirectsName(d.FullName))throw new ArgumentException("Add-on path contains a link");
            if(File.Exists(path) && RedirectsName(path))throw new ArgumentException("Add-on file is a link");
        }
        static string ReadBounded(string path,int limit) {
            PlainPath(path);
            using(var f=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read)) {
                if(f.Length>limit)throw new ArgumentException("Add-on file limit");
                using(var r=new StreamReader(f,Lib.Utf8,true))return r.ReadToEnd();
            }
        }
        public AddOnPackage Load(string id) {
            Lib.Id(Lib.Map("id",id),"id","[a-z][a-z0-9-]{0,39}");
            string dir=Path.Combine(Root,id), manifest=ReadBounded(Path.Combine(dir,"addon.json"),16384);
            var m=Lib.Parse(manifest);
            string api=Lib.Str(m,"api_version");
            if((api!="probe-addon/1" && api!="probe-addon/2") || Lib.Str(m,"id")!=id)throw new ArgumentException("Unsupported add-on manifest");
            ValidateEndpoint(Lib.Str(m,"endpoint"));
            if(m.ContainsKey("endpoints")) {
                var endpoints=Lib.Obj(m["endpoints"]);
                if(endpoints.Count>8)throw new ArgumentException("Too many endpoints");
                foreach(var entry in endpoints) {
                    Lib.Id(Lib.Map("id",entry.Key),"id","[a-z][a-z0-9-]{0,39}");
                    ValidateEndpoint(Convert.ToString(entry.Value));
                }
            }
            ValidateFields(m,"settings");ValidateFields(m,"inputs");
            if(m.ContainsKey("operations")) {
                var operations=Lib.Obj(m["operations"]);
                if(operations.Count>8)throw new ArgumentException("Too many operations");
                foreach(var entry in operations) {
                    Lib.Id(Lib.Map("id",entry.Key),"id","[a-z][a-z0-9-]{0,39}");
                    ValidateFields(Lib.Obj(entry.Value),"inputs");
                }
            }
            foreach(string section in new[]{"public_query","secret_query"})
                foreach(var pair in Lib.Obj(m[section])) {
                    var field=Fields(m,"settings").SingleOrDefault(f=>Lib.Str(f,"key")==Convert.ToString(pair.Value));
                    if(field==null || Lib.Bool(field,"secret")!=(section=="secret_query"))throw new ArgumentException("Invalid credential mapping");
                }
            string source=ReadBounded(Path.Combine(dir,"addon.js"),65536);
            string viewer=null;
            if(m.ContainsKey("viewer_file")) {
                string file=Lib.Id(m,"viewer_file","[a-z][a-z0-9-]{0,39}\\.html");
                viewer=ReadBounded(Path.Combine(dir,file),65536);
            }
            var hashInput=Lib.Map("manifest",m,"source",source);if(viewer!=null)hashInput["viewer"]=viewer;
            return new AddOnPackage {Id=id,Manifest=m,Source=source,ViewerSource=viewer,Hash=Lib.Digest(hashInput)};
        }
        static void ValidateEndpoint(string url) {
            var endpoint=new Uri(url);
            IPAddress ip;
            if(endpoint.Scheme!="https" || !endpoint.IsDefaultPort || endpoint.UserInfo!="" || endpoint.Query!="" || endpoint.Fragment!="" ||
                endpoint.Host.IndexOf('.')<0 || endpoint.Host.EndsWith(".local",StringComparison.OrdinalIgnoreCase) || IPAddress.TryParse(endpoint.Host,out ip))
                throw new ArgumentException("Add-on endpoint must be a public HTTPS URL without query or credentials");
        }
        static void ValidateFields(Dictionary<string,object> m,string section) {
            var names=new HashSet<string>();
            foreach(var field in Fields(m,section)) {
                string key=Lib.Id(field,"key","[a-z][a-z0-9_]{0,39}");
                if(!names.Add(key))throw new ArgumentException("Duplicate field");
            }
            if(names.Count>16)throw new ArgumentException("Too many fields");
        }
        public static Dictionary<string,object>[] Fields(Dictionary<string,object> manifest,string key) {
            return ((object[])manifest[key]).Select(Lib.Obj).ToArray();
        }
        public object[] List() {
            if(!Directory.Exists(Root))return new object[0];
            return Directory.GetDirectories(Root).Take(64).Select(path=> {
                string id=Path.GetFileName(path);
                try {var p=Load(id);var s=ReadSettings(id);return (object)Lib.Map("addon_id",id,"name",Lib.Str(p.Manifest,"name"),
                    "version",Lib.Str(p.Manifest,"version"),"endpoint",Lib.Str(p.Manifest,"endpoint"),"inputs",p.Manifest["inputs"],
                    "endpoints",Lib.Get(p.Manifest,"endpoints",Lib.Map()),"operations",Lib.Get(p.Manifest,"operations",Lib.Map()),
                    "interactive_viewer",p.ViewerSource!=null,
                    "enabled",Lib.Bool(s,"enabled") && Lib.Str(s,"approved_hash")==p.Hash,"source_hash",p.Hash,
                    "configuration_required",!Ready(p,s));}
                catch {return (object)Lib.Map("addon_id",id,"enabled",false,"error","Add-on or settings invalid/unreadable");}
            }).ToArray();
        }
        string SettingsPath(string id){Lib.Id(Lib.Map("id",id),"id","[a-z][a-z0-9-]{0,39}");return Path.Combine(SettingsRoot,id+".json");}
        public Dictionary<string,object> ReadSettings(string id) {
            lock(settingsLock) {
                string path=SettingsPath(id);
                if(!File.Exists(path))return Lib.Map("enabled",false,"approved_hash","","values",Lib.Map(),"secrets",Lib.Map());
                return Lib.Parse(ReadBounded(path,65536));
            }
        }
        static byte[] Entropy(string id,string key){return Encoding.UTF8.GetBytes("probe-addon/1:"+id+":"+key);}
        static string Decrypt(string id,string key,string value) {
            byte[] raw=ProtectedData.Unprotect(Convert.FromBase64String(value),Entropy(id,key),DataProtectionScope.CurrentUser);
            try{return Lib.Utf8.GetString(raw);}finally{Array.Clear(raw,0,raw.Length);}
        }
        static bool Ready(AddOnPackage p,Dictionary<string,object> s) {
            var values=Lib.Obj(s["values"]);var secrets=Lib.Obj(s["secrets"]);
            return Fields(p.Manifest,"settings").All(f=>!Lib.Bool(f,"required") ||
                Lib.Str(Lib.Bool(f,"secret")?secrets:values,Lib.Str(f,"key")).Length>0);
        }
        public void SaveSettings(AddOnPackage p,bool enabled,Dictionary<string,string> input,ISet<string> clear) {
            lock(settingsLock) {
                if(Load(p.Id).Hash!=p.Hash)throw new ArgumentException("Add-on changed. Reopen settings before enabling.");
                var old=ReadSettings(p.Id);var values=Lib.Map();var secrets=Lib.Map();
                foreach(var f in Fields(p.Manifest,"settings")) {
                    string key=Lib.Str(f,"key"),value;input.TryGetValue(key,out value);value=value??"";
                    if(value.Length>2048)throw new ArgumentException("Setting too long");
                    if(Lib.Bool(f,"secret")) {
                        if(value.Length>0) {
                            byte[] raw=Lib.Utf8.GetBytes(value);
                            try{secrets[key]=Convert.ToBase64String(ProtectedData.Protect(raw,Entropy(p.Id,key),DataProtectionScope.CurrentUser));}
                            finally{Array.Clear(raw,0,raw.Length);}
                        }else if(!clear.Contains(key))secrets[key]=Lib.Str(Lib.Obj(old["secrets"]),key);
                    }else values[key]=value.Trim();
                }
                var s=Lib.Map("enabled",enabled,"approved_hash",p.Hash,"values",values,"secrets",secrets);
                if(enabled && !Ready(p,s))throw new ArgumentException("Required settings are missing");
                Directory.CreateDirectory(SettingsRoot);PlainPath(SettingsPath(p.Id));Lib.Atomic(SettingsPath(p.Id),s);
            }
        }
        public async Task<object> QueryAsync(string id,Dictionary<string,object> input,CancellationToken token) {
            using(var deadline=CancellationTokenSource.CreateLinkedTokenSource(token)) {
                deadline.CancelAfter(25000);token=deadline.Token;
                await gate.WaitAsync(token).ConfigureAwait(false);
                var secretValues=new List<string>();
                try {
                    var p=Load(id);var s=ReadSettings(id);
                    if(!Lib.Bool(s,"enabled") || Lib.Str(s,"approved_hash")!=p.Hash)throw new ArgumentException("Enable this source revision in Probe AddOns settings first");
                    if(!Ready(p,s))throw new ArgumentException("Configure required settings in Probe");
                    var prepared=Lib.Obj(await Script(p,"prepare",input,token).ConfigureAwait(false));
                    string endpoint=ResolveEndpoint(p,prepared);
                    var query=new Dictionary<string,object>(Lib.Obj(prepared["query"]));
                    if(query.Count>24 || query.Any(kv=>!(kv.Value is string)))throw new ArgumentException("Invalid query parameters");
                    foreach(var pair in Lib.Obj(p.Manifest["public_query"]))query.Add(pair.Key,Lib.Str(Lib.Obj(s["values"]),Convert.ToString(pair.Value)));
                    foreach(var pair in Lib.Obj(p.Manifest["secret_query"])) {
                        string key=Convert.ToString(pair.Value),secret=Decrypt(id,key,Lib.Str(Lib.Obj(s["secrets"]),key));
                        secretValues.Add(secret);query.Add(pair.Key,secret);
                    }
                    string uri=endpoint+"?"+String.Join("&",query.Select(kv=>Uri.EscapeDataString(kv.Key)+"="+Uri.EscapeDataString((string)kv.Value)));
                    if(uri.Length>8192)throw new ArgumentException("Query limit exceeded");
                    string response=await Fetch(new Uri(uri),token).ConfigureAwait(false);
                    // Strip reflected credentials before sending anything to source code or to callers.
                    foreach(string secret in secretValues)response=Redact(response,secret);
                    object result=await Script(p,"parse",Lib.Map("body",response,"request",prepared),token).ConfigureAwait(false);
                    string json=Lib.Json(result);foreach(string secret in secretValues)json=Redact(json,secret);
                    var data=Lib.Parse(json);
                    return Lib.Map("ok",Lib.Str(data,"status")!="error","addon_id",id,"source_hash",p.Hash,"retrieved_at",DateTime.UtcNow.ToString("o"),"data",data);
                }catch(OperationCanceledException){return Lib.Map("ok",false,"error","Query canceled or timed out");}
                catch(CryptographicException){return Lib.Map("ok",false,"error","Credential cannot be decrypted. Re-enter it in Probe on this Windows account.");}
                catch(Exception ex) {
                    if(token.IsCancellationRequested)return Lib.Map("ok",false,"error","Query canceled or timed out");
                    // Network/library exceptions can contain URLs, query strings or response bodies.
                    string message=ex is WebException?"HTTPS request failed; check connectivity, API key and domain":
                        ex is LibraryFault?"Add-on: "+ex.Message.Substring(0,Math.Min(ex.Message.Length,512)):
                        ex is ArgumentException?ex.Message:"Add-on query failed; check local settings and service availability";
                    foreach(string secret in secretValues)message=Redact(message,secret);
                    return Lib.Map("ok",false,"error",message);
                }finally{gate.Release();}
            }
        }
        internal static string Redact(string text,string secret) {
            if(String.IsNullOrEmpty(secret))return text;
            return text.Replace(secret,"[redacted]").Replace(Uri.EscapeDataString(secret),"[redacted]")
                .Replace(Lib.Json(secret).Trim('"'),"[redacted]");
        }
        internal static string ResolveEndpoint(AddOnPackage p,Dictionary<string,object> prepared) {
            string alias=Lib.Str(prepared,"endpoint");
            if(alias.Length==0)return Lib.Str(p.Manifest,"endpoint");
            var endpoints=Lib.Obj(Lib.Get(p.Manifest,"endpoints",Lib.Map()));
            if(!endpoints.ContainsKey(alias))throw new ArgumentException("Undeclared add-on endpoint");
            return Lib.Str(endpoints,alias);
        }
        public string PrepareViewer(string id) {
            var p=Load(id);var s=ReadSettings(id);
            if(p.ViewerSource==null || !Lib.Bool(s,"enabled") || Lib.Str(s,"approved_hash")!=p.Hash)
                throw new ArgumentException("설정에서 현재 애드온 소스를 활성화하고 저장하세요.");
            // A private snapshot contains source only. Never inject credentials or settings into HTML.
            string dir=Path.Combine(SettingsRoot,"Views");Directory.CreateDirectory(dir);
            string file=Path.Combine(dir,id+"-"+Guid.NewGuid().ToString("N")+".html");PlainPath(file);
            using(var stream=new FileStream(file,FileMode.CreateNew,FileAccess.Write,FileShare.None)) {
                byte[] bytes=Lib.Utf8.GetBytes(p.ViewerSource);stream.Write(bytes,0,bytes.Length);
            }
            return file;
        }
        internal static Task<object> Script(AddOnPackage p,string stage,object input,CancellationToken token) {
            return LibraryWorker.RunAsync(Lib.Map("kind","addon","source",p.Source,"stage",stage,"input",input,"timeout_ms",1000,"memory_mib",32),token);
        }
        internal static async Task<string> Download(Uri uri,CancellationToken token) {
            // csc-built .NET Framework applications otherwise default to SSL3/TLS1.0.
            // Keep certificate validation intact while requiring modern transport.
            ServicePointManager.SecurityProtocol=SecurityProtocolType.Tls12;
            var request=(HttpWebRequest)WebRequest.Create(uri);
            request.Method="GET";request.AllowAutoRedirect=false;request.Timeout=10000;request.ReadWriteTimeout=10000;
            request.AutomaticDecompression=DecompressionMethods.GZip|DecompressionMethods.Deflate;
            using(var timeout=CancellationTokenSource.CreateLinkedTokenSource(token)) {
                timeout.CancelAfter(10000);
                using(timeout.Token.Register(request.Abort))
                using(var response=(HttpWebResponse)await request.GetResponseAsync().ConfigureAwait(false)) {
                    if(response.StatusCode!=HttpStatusCode.OK)throw new WebException("HTTP failure");
                    using(var stream=response.GetResponseStream())using(var output=new MemoryStream()) {
                        var bytes=new byte[8192];int n;
                        while((n=await stream.ReadAsync(bytes,0,bytes.Length,timeout.Token).ConfigureAwait(false))>0) {
                            if(output.Length+n>262144)throw new ArgumentException("Response too large; narrow the query");
                            output.Write(bytes,0,n);
                        }
                        return Lib.Utf8.GetString(output.ToArray());
                    }
                }
            }
        }
    }
}
