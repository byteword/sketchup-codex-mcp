using System;
using System.IO;
using System.Drawing;
using System.Linq;
using System.Collections.Generic;
using System.Threading;
using System.Windows.Forms;

namespace SketchUpPipeProbe
{
    public sealed class AddOnForm:Form
    {
        sealed class Choice {public string Id,Label;public override string ToString(){return Label;}}
        readonly AddOnService service;
        readonly ComboBox packages=new ComboBox {DropDownStyle=ComboBoxStyle.DropDownList,Width=315};
        readonly ComboBox operation=new ComboBox {DropDownStyle=ComboBoxStyle.DropDownList,Width=315};
        readonly FlowLayoutPanel fields=Stack(),queries=Stack();
        readonly TextBox output=ResultBox(),selection=ResultBox();
        readonly Label status=new Label {Dock=DockStyle.Top,Height=72,Padding=new Padding(10),Text="조회할 기능과 위치를 선택하세요."};
        readonly GeoJsonView map=new GeoJsonView();
        readonly CheckBox enabled=new CheckBox {Text="이 소스 버전의 서비스·화면 사용",AutoSize=true};
        readonly Button save=Button("설정 저장"),run=Button("조회"),cancel=Button("취소"),viewer=Button("지도 화면 열기"),export=Button("GeoJSON 저장"),followup=Button("결과 위치로 다음 조회");
        readonly Dictionary<string,TextBox> settings=new Dictionary<string,TextBox>(),inputs=new Dictionary<string,TextBox>();
        readonly Dictionary<string,CheckBox> clears=new Dictionary<string,CheckBox>();
        AddOnPackage selected;Dictionary<string,object> geojson,next;
        CancellationTokenSource active;
        static FlowLayoutPanel Stack(){return new FlowLayoutPanel {Dock=DockStyle.Top,AutoSize=true,FlowDirection=FlowDirection.TopDown,WrapContents=false,Padding=new Padding(8)};}
        static TextBox ResultBox(){return new TextBox {Multiline=true,ReadOnly=true,ScrollBars=ScrollBars.Both,Dock=DockStyle.Fill,WordWrap=false};}
        static Button Button(string name){return new Button {Text=name,AutoSize=true,Height=32};}
        public AddOnForm(AddOnService addOns) {
            service=addOns;Text="Probe AddOns — 지도·외부 데이터 조회";Size=new Size(1180,850);MinimumSize=new Size(1000,700);
            Font=new Font("Malgun Gothic",9);StartPosition=FormStartPosition.CenterParent;
            var layout=new TableLayoutPanel {Dock=DockStyle.Fill,ColumnCount=2,RowCount=1,Padding=new Padding(10)};
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,365));layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));Controls.Add(layout);
            var scroll=new Panel {Dock=DockStyle.Fill,AutoScroll=true};scroll.Controls.Add(fields);layout.Controls.Add(scroll,0,0);
            var right=new Panel {Dock=DockStyle.Fill};layout.Controls.Add(right,1,0);
            var tabs=new TabControl {Dock=DockStyle.Fill};var mapPage=new TabPage("경계 지도");var rawPage=new TabPage("전체 결과");var detailPage=new TabPage("선택 속성");
            mapPage.Controls.Add(map);rawPage.Controls.Add(output);detailPage.Controls.Add(selection);tabs.TabPages.AddRange(new[]{mapPage,rawPage,detailPage});
            var actions=new FlowLayoutPanel {Dock=DockStyle.Bottom,AutoSize=true};var fit=Button("전체 보기");
            actions.Controls.Add(fit);actions.Controls.Add(export);actions.Controls.Add(followup);right.Controls.Add(tabs);right.Controls.Add(actions);right.Controls.Add(status);
            fit.Click+=delegate{map.ResetView();};export.Enabled=followup.Enabled=cancel.Enabled=false;
            fields.Controls.Add(packages);
            if(Directory.Exists(service.Root))foreach(string dir in Directory.GetDirectories(service.Root).Take(64)) {
                try{packages.Items.Add(service.Load(Path.GetFileName(dir)));}catch{output.AppendText("읽을 수 없는 애드온: "+Path.GetFileName(dir)+Environment.NewLine);}
            }
            packages.SelectedIndexChanged+=delegate {try{ShowPackage();run.Enabled=save.Enabled=true;}catch{selected=null;run.Enabled=save.Enabled=false;status.Text="애드온 또는 설정을 읽지 못했습니다.";}};
            operation.SelectedIndexChanged+=delegate{ShowInputs();};
            save.Click+=delegate {
                if(selected==null)return;
                try {
                    service.SaveSettings(selected,enabled.Checked,settings.ToDictionary(p=>p.Key,p=>p.Value.Text),new HashSet<string>(clears.Where(p=>p.Value.Checked).Select(p=>p.Key)));
                    foreach(var pair in clears){settings[pair.Key].Text="";pair.Value.Checked=false;}
                    status.Text="설정 저장됨. 인증키는 현재 Windows 사용자 DPAPI로 암호화했습니다.";
                }catch{status.Text="필수 설정을 확인하세요. 소스가 바뀌었다면 창을 다시 열고 활성화하세요.";}
            };
            run.Click+=async delegate {
                if(selected==null || active!=null)return;
                active=new CancellationTokenSource();var current=active;
                packages.Enabled=operation.Enabled=save.Enabled=run.Enabled=viewer.Enabled=false;cancel.Enabled=true;status.Text="조회 중…";
                next=null;geojson=null;export.Enabled=followup.Enabled=false;map.SetData(null);selection.Clear();output.Clear();
                try {
                    var args=inputs.ToDictionary(p=>p.Key,p=>(object)p.Value.Text);
                    var choice=operation.SelectedItem as Choice;if(choice!=null)args["operation"]=choice.Id;
                    var result=Lib.Obj(await service.QueryAsync(selected.Id,args,current.Token));
                    if(!IsDisposed) {
                        output.Text=Pretty(Lib.Json(result));
                        var data=JsonLines.Object(result,"data");
                        if(!Lib.Bool(result,"ok"))status.Text=data==null?Lib.Str(result,"error"):Lib.Str(data,"message");
                        else {
                            geojson=data==null?null:JsonLines.Object(data,"geojson");next=data==null?null:JsonLines.Object(data,"followup");
                            status.Text=data==null?"완료":Lib.Str(data,"source")+"\n"+Lib.Str(data,"note");
                            export.Enabled=geojson!=null;followup.Enabled=next!=null;
                            try{map.SetData(geojson);}catch{status.Text+="\n경계 미리보기 실패. 전체 결과를 확인하세요.";}
                        }
                    }
                }catch(OperationCanceledException){if(!IsDisposed)status.Text="조회 취소됨";}
                catch{if(!IsDisposed)status.Text="조회 실패. 설정 및 서비스 연결을 확인하세요.";}
                finally{active=null;current.Dispose();if(!IsDisposed){packages.Enabled=operation.Enabled=save.Enabled=run.Enabled=true;viewer.Enabled=selected!=null && selected.ViewerSource!=null;cancel.Enabled=false;}}
            };
            cancel.Click+=delegate{if(active!=null)active.Cancel();};
            viewer.Click+=delegate {if(selected==null)return;try{System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(service.PrepareViewer(selected.Id)){UseShellExecute=true});}catch{status.Text="현재 소스를 활성화·저장한 뒤 지도 화면을 열어주세요.";}};
            map.FeatureSelected+=props=>{selection.Text=Pretty(Lib.Json(props));tabs.SelectedTab=detailPage;};
            export.Click+=delegate {
                if(geojson==null)return;
                using(var dialog=new SaveFileDialog {Filter="GeoJSON|*.geojson",FileName="vworld-query.geojson",OverwritePrompt=true}) {
                    if(dialog.ShowDialog(this)!=DialogResult.OK)return;
                    try{File.WriteAllText(dialog.FileName,Pretty(Lib.Json(geojson)),Lib.Utf8);status.Text="GeoJSON 저장됨: "+dialog.FileName;}catch{status.Text="파일을 저장하지 못했습니다.";}
                }
            };
            followup.Click+=delegate {
                if(next==null)return;var request=next;
                foreach(Choice choice in operation.Items)if(choice.Id==Lib.Str(request,"operation")){operation.SelectedItem=choice;break;}
                foreach(var pair in Lib.Obj(request["inputs"]))if(inputs.ContainsKey(pair.Key))inputs[pair.Key].Text=Convert.ToString(pair.Value);
                status.Text="결과 위치를 입력했습니다. 조회를 눌러 확인하세요.";
            };
            FormClosing+=delegate{if(active!=null)active.Cancel();};
            if(packages.Items.Count>0)packages.SelectedIndex=0;
            else{run.Enabled=save.Enabled=false;status.Text="실행파일 옆 AddOns 폴더에 애드온을 설치하고 창을 다시 여세요.";}
        }
        void ShowPackage() {
            selected=(AddOnPackage)packages.SelectedItem;
            foreach(Control keep in new Control[]{enabled,save,run,cancel,viewer,operation,queries})if(keep.Parent!=null)keep.Parent.Controls.Remove(keep);
            while(fields.Controls.Count>1){var c=fields.Controls[1];fields.Controls.Remove(c);c.Dispose();}
            settings.Clear();inputs.Clear();clears.Clear();
            var s=service.ReadSettings(selected.Id);enabled.Checked=Lib.Bool(s,"enabled") && Lib.Str(s,"approved_hash")==selected.Hash;
            fields.Controls.Add(enabled);
            foreach(var f in AddOnService.Fields(selected.Manifest,"settings")) {
                string key=Lib.Str(f,"key");bool secret=Lib.Bool(f,"secret");settings[key]=Field(fields,Lib.Str(f,"label"),secret?"":Lib.Str(Lib.Obj(s["values"]),key),secret);
                if(secret){var clear=new CheckBox {Text="저장된 키 삭제"+(Lib.Str(Lib.Obj(s["secrets"]),key).Length>0?" (등록됨)":" (미등록)"),AutoSize=true};clears[key]=clear;fields.Controls.Add(clear);}
            }
            fields.Controls.Add(save);viewer.Text=Lib.Str(selected.Manifest,"viewer_label","지도 화면 열기");viewer.Enabled=selected.ViewerSource!=null;
            if(selected.ViewerSource!=null)fields.Controls.Add(viewer);
            operation.Items.Clear();
            var ops=Lib.Obj(Lib.Get(selected.Manifest,"operations",Lib.Map()));
            foreach(var op in ops)operation.Items.Add(new Choice {Id=op.Key,Label=Lib.Str(Lib.Obj(op.Value),"label")});
            if(operation.Items.Count>0){fields.Controls.Add(new Label {AutoSize=true,Text="조회 기능"});fields.Controls.Add(operation);}
            fields.Controls.Add(queries);
            var buttons=new FlowLayoutPanel {AutoSize=true,Width=320};buttons.Controls.Add(run);buttons.Controls.Add(cancel);fields.Controls.Add(buttons);
            if(operation.Items.Count>0)operation.SelectedIndex=0;else ShowInputs();
        }
        void ShowInputs() {
            while(queries.Controls.Count>0){var c=queries.Controls[0];queries.Controls.Remove(c);c.Dispose();}inputs.Clear();
            if(selected==null)return;
            var choice=operation.SelectedItem as Choice;
            var definition=choice==null?selected.Manifest:Lib.Obj(Lib.Obj(selected.Manifest["operations"])[choice.Id]);
            foreach(var f in AddOnService.Fields(definition,"inputs"))inputs[Lib.Str(f,"key")]=Field(queries,Lib.Str(f,"label"),Lib.Str(f,"default"),false);
        }
        TextBox Field(FlowLayoutPanel panel,string label,string value,bool secret) {
            panel.Controls.Add(new Label {Text=label,AutoSize=true,MaximumSize=new Size(310,0),Margin=new Padding(3,8,3,3)});
            var box=new TextBox {Width=310,Text=value,UseSystemPasswordChar=secret};panel.Controls.Add(box);return box;
        }
        static string Pretty(string json) {
            var b=new System.Text.StringBuilder();bool quoted=false,escape=false;int depth=0;
            foreach(char c in json) {
                if(quoted){b.Append(c);if(escape)escape=false;else if(c=='\\')escape=true;else if(c=='"')quoted=false;continue;}
                if(c=='"'){quoted=true;b.Append(c);}else if(c=='{'||c=='['){b.Append(c).AppendLine();depth++;b.Append(' ',depth*2);}
                else if(c=='}'||c==']'){depth--;b.AppendLine().Append(' ',depth*2).Append(c);}
                else if(c==',')b.Append(c).AppendLine().Append(' ',depth*2);else b.Append(c);
            }return b.ToString();
        }
    }
}
