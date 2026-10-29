using System;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace SketchUpPipeProbe
{
    static class Program
    {
        [STAThread]
        static void Main(string[] args)
        {
            if(LibraryWorker.TryMain(args)) return;
            bool created;
            using (var mutex = new Mutex(true, "Local\\SketchUpCodexMcp.PipeProbe.v1", out created))
            {
                if (!created) { if (!args.Contains("--quiet")) MessageBox.Show("SketchUp bridge GUI is already running."); return; }
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new MainForm());
                mutex.ReleaseMutex();
            }
        }
    }

    sealed class MainForm : Form
    {
        readonly DataGridView grid = new DataGridView();
        readonly TextBox logs = new TextBox();
        readonly Label status = new Label();
        readonly Label heading = new Label();
        readonly System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer();
        readonly PipeHub hub;
        readonly ControlHub control;
        readonly Button demo;
        readonly Button errorButton;
        bool closing;

        public MainForm()
        {
            Text = "SketchUp MCP Bridge " + BuildInfo.Version + " — 다중 인스턴스 연결";
            Size = new Size(1200, 760);
            MinimumSize = new Size(860, 600);
            Font = new Font("Malgun Gothic", 9);
            StartPosition = FormStartPosition.CenterScreen;
            var layout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 5, Padding = new Padding(14) };
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 84));
            layout.RowStyles.Add(new RowStyle(SizeType.Percent, 60));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 80));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 34));
            layout.RowStyles.Add(new RowStyle(SizeType.Percent, 40));
            heading.Dock = DockStyle.Fill;
            heading.Text = "MCP 연결 대기 · 객체 검색 / 조회 / 생성·복제 / 명령 전달 (시험)";
            layout.Controls.Add(heading, 0, 0);
            grid.Dock = DockStyle.Fill;
            grid.ReadOnly = true;
            grid.AllowUserToAddRows = false;
            grid.AllowUserToDeleteRows = false;
            grid.MultiSelect = false;
            grid.SelectionMode = DataGridViewSelectionMode.FullRowSelect;
            grid.RowHeadersVisible = false;
            foreach (string name in new[] { "세션", "PID", "모델", "파일 경로", "SU / Ruby", "제어권", "진행률", "연결", "최근 오류" })
                grid.Columns.Add(name, name);
            grid.Columns[0].Width = 95;
            grid.Columns[1].Width = 65;
            grid.Columns[2].Width = 130;
            grid.Columns[3].Width = 220;
            grid.Columns[4].Width = 100;
            grid.Columns[5].Width = 75;
            grid.Columns[6].Width = 65;
            grid.Columns[7].Width = 120;
            grid.Columns[8].AutoSizeMode = DataGridViewAutoSizeColumnMode.Fill;
            layout.Controls.Add(grid, 0, 1);
            var actions = new FlowLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(0, 8, 0, 0) };
            actions.Controls.Add(CommandButton("선택 창에 한글 Ping", "ping"));
            demo = CommandButton("20초 작업 시험", "demo");
            actions.Controls.Add(demo);
            actions.Controls.Add(CommandButton("선택 창 작업 중지", "cancel"));
            errorButton = CommandButton("오류 표시 시험", "test_error");
            actions.Controls.Add(errorButton);
            var save = new Button { Text = "로그 저장", AutoSize = true, Height = 32 };
            save.Click += delegate {
                using (var dialog = new SaveFileDialog { Filter = "Text log|*.txt", FileName = "pipe-probe-log.txt" })
                {
                    if (dialog.ShowDialog(this) != DialogResult.OK) return;
                    try { File.WriteAllText(dialog.FileName, logs.Text, new System.Text.UTF8Encoding(true)); }
                    catch (Exception ex) { MessageBox.Show(this, ex.Message, "로그 저장 오류"); }
                }
            };
            actions.Controls.Add(save);
            var config = new Button { Text = "MCP 등록 설정 복사", AutoSize = true, Height = 32 };
            config.Click += delegate {
                string path = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "SketchUpMcp.exe");
                string text = "[mcp_servers.sketchup_local]\r\ncommand = " + JsonLines.Serialize(path) +
                    "\r\nargs = [\"--start-gui\"]\r\nstartup_timeout_sec = 15\r\ntool_timeout_sec = 30\r\n";
                try { Clipboard.SetText(text); Log("MCP 설정 복사됨. command: " + path + " / args: --start-gui"); }
                catch (Exception error) { Log("설정 복사 오류: " + error.Message); }
            };
            actions.Controls.Add(config);
            var libraryFolder=new Button {Text="기법 라이브러리 폴더",AutoSize=true,Height=32};
            libraryFolder.Click+=delegate {
                try {System.Diagnostics.Process.Start("explorer.exe", "\""+control.LibraryDirectory+"\"");}
                catch(Exception error){Log("라이브러리 폴더 열기 오류: "+error.Message);}
            };
            actions.Controls.Add(libraryFolder);
            var notices=new Button {Text="오픈소스 안내",AutoSize=true,Height=32};
            notices.Click+=delegate {
                var dialog=new Form {Text="스크립트 엔진 오픈소스 안내",Width=780,Height=600,StartPosition=FormStartPosition.CenterParent};
                dialog.Controls.Add(new TextBox {Multiline=true,ReadOnly=true,ScrollBars=ScrollBars.Both,Dock=DockStyle.Fill,Text=Lib.Resource("NOTICES")});
                using(dialog)dialog.ShowDialog(this);
            };
            actions.Controls.Add(notices);
            layout.Controls.Add(actions, 0, 2);
            status.Dock = DockStyle.Fill;
            layout.Controls.Add(status, 0, 3);
            logs.Multiline = true;
            logs.ReadOnly = true;
            logs.ScrollBars = ScrollBars.Both;
            logs.WordWrap = false;
            logs.Dock = DockStyle.Fill;
            logs.Font = new Font("Consolas", 9);
            layout.Controls.Add(logs, 0, 4);
            Controls.Add(layout);
            hub = new PipeHub(Log);
            control = new ControlHub(hub, Log);
            hub.McpStateProvider = () => control.Clients.Values.Select(c => new { name = c.Name, pid = c.Pid }).ToArray();
            Shown += delegate {
                Wire.Observe(Task.Run(() => hub.RunAsync()), error => Log("Hub task error: " + error.Message));
                Wire.Observe(Task.Run(() => control.RunAsync()), error => Log("MCP task error: " + error.Message));
                timer.Start();
            };
            timer.Interval = 500;
            timer.Tick += delegate { RefreshPeers(); };
            FormClosing += delegate { closing = true; timer.Stop(); control.Dispose(); hub.Dispose(); };
        }

        Button CommandButton(string label, string method)
        {
            var button = new Button { Text = label, AutoSize = true, Height = 32 };
            button.Click += async delegate {
                Peer peer = Selected();
                if (peer == null) { Log("연결된 SketchUp 행을 선택하세요."); return; }
                button.Enabled = false;
                try {
                    var response = await peer.CommandAsync(method);
                    if (Wire.Text(response, "ok") != "True") Log("SketchUp 거부: " + Wire.Text(response, "status"));
                }
                catch (Exception error) { Log("명령 전송 오류: " + error.Message); }
                finally { if (!closing) button.Enabled = true; }
            };
            return button;
        }

        Peer Selected()
        {
            if (grid.SelectedRows.Count == 0) return null;
            string id = grid.SelectedRows[0].Tag as string;
            Peer peer;
            return id != null && hub.Peers.TryGetValue(id, out peer) ? peer : null;
        }

        void RefreshPeers()
        {
            Peer selected = Selected();
            string selectedId = selected == null ? null : selected.SessionId;
            grid.Rows.Clear();
            foreach (Peer peer in hub.Peers.Values.OrderBy(p => p.ClientPid).ThenBy(p => p.SessionId))
            {
                var s = peer.State;
                double age = (DateTime.UtcNow - peer.LastSeenUtc).TotalSeconds;
                int row = grid.Rows.Add(peer.SessionId.Substring(0, 8), peer.ClientPid,
                    Empty(Wire.Text(s, "title"), "제목 없음"), Empty(Wire.Text(s, "path"), "미저장"),
                    Wire.Text(s, "sketchup_version") + " / " + Wire.Text(s, "ruby_version"),
                    Wire.Text(s, "authority"), Wire.Text(s, "progress") + "%",
                    age > 15 ? "응답 지연 " + (int)age + "s" : "연결됨", Wire.Text(s, "last_error"));
                grid.Rows[row].Tag = peer.SessionId;
                grid.Rows[row].Cells[0].ToolTipText = peer.SessionId;
            }
            // No implicit target switch if the selected instance disappears.
            grid.ClearSelection();
            foreach (DataGridViewRow row in grid.Rows)
                if ((string)row.Tag == selectedId) row.Selected = true;
            Peer current = Selected();
            bool allowed = current != null && Wire.Text(current.State, "authority") == "mcp";
            demo.Enabled = errorButton.Enabled = allowed;
            var clients = control.Clients.Values.ToArray();
            heading.Text = "SketchUp MCP Bridge " + BuildInfo.Version + " · 객체 검색 / 조회 / 생성·복제 / 명령 전달 (시험)\n" +
                (clients.Length == 0 ? "MCP 연결 대기 — ChatGPT에 SketchUpMcp.exe를 STDIO로 등록하세요." :
                 "MCP 연결 " + clients.Length + "개: " + String.Join(" | ", clients.Select(c =>
                     c.Name + " " + c.Version + " / PID " + c.Pid + " / 작업 " + c.Active + " / " + c.LastTool))) +
                "\nMCP 수신: " + control.Status + (control.LastError.Length == 0 ? "" : " · 최근 오류: " + control.LastError);
            status.Text = hub.Status + " · 연결 " + hub.Peers.Count + "개 · 대상을 클릭하세요 · 모달 대화상자 사용 중에는 응답이 지연될 수 있습니다.";
        }

        static string Empty(string text, string fallback) { return text.Length == 0 ? fallback : text; }

        void Log(string text)
        {
            if (closing || IsDisposed || !IsHandleCreated) return;
            try
            {
                BeginInvoke((Action)(() => {
                    if (closing) return;
                    if (logs.TextLength > 60000) logs.Text = logs.Text.Substring(logs.TextLength - 40000);
                    logs.AppendText(DateTime.Now.ToString("HH:mm:ss") + " " + text + Environment.NewLine);
                }));
            }
            catch (InvalidOperationException) { }
        }
    }
}
