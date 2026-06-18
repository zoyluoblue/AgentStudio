import Foundation

/// R5 + v1.4 — guided start + template library. Each template carries a bilingual title/description,
/// an SF Symbol, a rich build goal (sent to the planner), AND a real, runnable starter project
/// (full files), so picking one drops a working app the user can Run immediately and the AI iterates on.
struct AppTemplate: Identifiable, Sendable {
    let id: String
    let icon: String
    let titleZh: String, titleEn: String
    let descZh: String, descEn: String
    let goalZh: String, goalEn: String

    func title(_ l: Lang) -> String { l.t(titleZh, titleEn) }
    func desc(_ l: Lang) -> String { l.t(descZh, descEn) }
    func goal(_ l: Lang) -> String { l.t(goalZh, goalEn) }

    /// The starter project's files (complete + runnable). Built per-template.
    func files(_ l: Lang) -> [ProjectFiles.ParsedFile] { TemplateLibrary.files(for: id, l) }
}

enum TemplateLibrary {
    static let all: [AppTemplate] = [
        AppTemplate(id: "homepage", icon: "person.crop.square.badge.camera",
            titleZh: "个人主页", titleEn: "Personal homepage",
            descZh: "干净的单页名片：简介、技能、联系方式。", descEn: "A clean one-page profile.",
            goalZh: "在现有个人主页基础上完善：填上真实的姓名/简介/技能/联系方式，配色更协调、排版更精致、加点微交互。",
            goalEn: "Polish the existing personal homepage: real name/bio/skills/contact, nicer palette and typography, subtle interactions."),
        AppTemplate(id: "todo", icon: "checklist",
            titleZh: "待办清单", titleEn: "To-do list",
            descZh: "能增删勾选、本地保存的待办应用。", descEn: "Add, check off, persist locally.",
            goalZh: "在现有可用的待办应用基础上增强：加分类/筛选(全部/未完成/已完成)、编辑任务、拖拽排序、更好看的样式。",
            goalEn: "Enhance the working to-do app: filters (all/active/done), edit, drag-to-reorder, nicer styling."),
        AppTemplate(id: "landing", icon: "sparkles",
            titleZh: "产品落地页", titleEn: "Product landing page",
            descZh: "卖点 + 行动按钮的营销页。", descEn: "Benefits and a CTA.",
            goalZh: "在现有落地页基础上完善：替换成真实产品文案、加更多区块(功能/评价/价格/FAQ)、响应式、专业现代。",
            goalEn: "Polish the landing page: real copy, more sections (features/testimonials/pricing/FAQ), responsive, professional."),
        AppTemplate(id: "game", icon: "gamecontroller",
            titleZh: "小游戏", titleEn: "Mini game",
            descZh: "能玩起来的网页小游戏。", descEn: "A playable browser game.",
            goalZh: "在现有猜数字游戏基础上做得更好玩：加难度选择、最佳成绩记录、动画与音效反馈、更活泼的界面。",
            goalEn: "Make the guess-the-number game more fun: difficulty levels, best-score record, animations/sound feedback, livelier UI."),
        AppTemplate(id: "dashboard", icon: "chart.bar.xaxis",
            titleZh: "数据看板", titleEn: "Data dashboard",
            descZh: "用图表展示数据。", descEn: "Show data with charts.",
            goalZh: "在现有数据看板基础上扩展：加更多指标卡片和图表类型(折线/饼图)、可切换数据、整齐专业的布局。",
            goalEn: "Extend the dashboard: more metric cards and chart types (line/pie), switchable data, tidy professional layout."),
        AppTemplate(id: "vite-react", icon: "atom",
            titleZh: "React 应用 (Vite)", titleEn: "React app (Vite)",
            descZh: "带构建/热重载的现代 React 起步工程。", descEn: "A modern React starter with Vite + HMR.",
            goalZh: "在现有 Vite + React 计数器应用基础上,实现我接下来描述的功能(组件化、状态管理,样式现代)。",
            goalEn: "On the existing Vite + React counter app, build the feature I'll describe next (componentized, stateful, modern styling)."),
    ]

    static func files(for id: String, _ l: Lang) -> [ProjectFiles.ParsedFile] {
        switch id {
        case "homepage": return [page("index.html", doc(l, title: l.t("我的主页", "My Homepage"), css: homepageCSS, body: homepageBody(l), js: ""))]
        case "todo": return [page("index.html", doc(l, title: l.t("待办清单", "To-do"), css: todoCSS, body: todoBody(l), js: todoJS))]
        case "landing": return [page("index.html", doc(l, title: l.t("产品落地页", "Landing"), css: landingCSS, body: landingBody(l), js: ""))]
        case "game": return [page("index.html", doc(l, title: l.t("猜数字", "Guess the Number"), css: gameCSS, body: gameBody(l), js: gameJS(l)))]
        case "dashboard": return [page("index.html", doc(l, title: l.t("数据看板", "Dashboard"), css: dashCSS, body: dashBody(l), js: dashJS))]
        case "vite-react": return viteReactFiles(l)
        default: return []
        }
    }

    // MARK: - builders

    private static func page(_ path: String, _ content: String) -> ProjectFiles.ParsedFile { .init(path: path, content: content) }

    private static func doc(_ l: Lang, title: String, css: String, body: String, js: String) -> String {
        let lang = l == .zh ? "zh-CN" : "en"
        let script = js.isEmpty ? "" : "\n  <script>\n\(js)\n  </script>"
        return """
        <!doctype html>
        <html lang="\(lang)">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(title)</title>
          <style>
        \(baseCSS)
        \(css)
          </style>
        </head>
        <body>
        \(body)\(script)
        </body>
        </html>
        """
    }

    private static let baseCSS = """
    :root{--bg:#f6f7f9;--card:#ffffff;--line:#e7e9f0;--text:#1b2230;--dim:#697086;--accent:#ff8a3d;--accent2:#4a7cff}
    *{box-sizing:border-box}
    body{margin:0;min-height:100vh;font-family:-apple-system,system-ui,"PingFang SC","Microsoft YaHei",Segoe UI,sans-serif;color:var(--text);background:var(--bg);line-height:1.65;-webkit-font-smoothing:antialiased}
    a{color:var(--accent2);text-decoration:none}
    button{font:inherit;cursor:pointer}
    """

    // MARK: - homepage
    private static let homepageCSS = """
    .wrap{max-width:720px;margin:0 auto;padding:64px 24px}
    header h1{font-size:40px;margin:0 0 6px}
    header p{color:var(--dim);font-size:18px;margin:0}
    section{margin-top:40px}
    section h2{font-size:14px;letter-spacing:.08em;text-transform:uppercase;color:var(--dim);margin:0 0 12px}
    .tags{display:flex;flex-wrap:wrap;gap:8px}
    .tags span{background:var(--card);border:1px solid var(--line);border-radius:999px;padding:6px 14px;font-size:14px}
    .links a{display:inline-block;margin-right:16px;font-weight:600}
    """
    private static func homepageBody(_ l: Lang) -> String {
        l.t("""
          <div class="wrap">
            <header>
              <h1>你的名字</h1>
              <p>一句话介绍你自己 —— 比如「设计师 / 摄影爱好者」。</p>
            </header>
            <section><h2>关于我</h2><p>在这里写两三句关于你的故事、正在做的事、感兴趣的方向。</p></section>
            <section><h2>技能</h2><div class="tags"><span>设计</span><span>写作</span><span>摄影</span><span>沟通</span></div></section>
            <section><h2>联系</h2><div class="links"><a href="mailto:you@example.com">邮箱</a><a href="#">微博</a><a href="#">GitHub</a></div></section>
          </div>
        """, """
          <div class="wrap">
            <header>
              <h1>Your Name</h1>
              <p>A one-line intro — e.g. "Designer / photography lover".</p>
            </header>
            <section><h2>About</h2><p>Two or three sentences about you, what you're working on, what you care about.</p></section>
            <section><h2>Skills</h2><div class="tags"><span>Design</span><span>Writing</span><span>Photography</span><span>Communication</span></div></section>
            <section><h2>Contact</h2><div class="links"><a href="mailto:you@example.com">Email</a><a href="#">Twitter</a><a href="#">GitHub</a></div></section>
          </div>
        """)
    }

    // MARK: - todo
    private static let todoCSS = """
    .app{max-width:520px;margin:48px auto;padding:0 20px}
    h1{font-size:28px;margin:0 0 4px}
    .sub{color:var(--dim);margin:0 0 20px}
    form{display:flex;gap:8px;margin-bottom:16px}
    input[type=text]{flex:1;padding:12px 14px;border:1px solid var(--line);border-radius:10px;font-size:15px;background:var(--card)}
    form button{padding:0 18px;border:none;border-radius:10px;background:var(--accent);color:#fff;font-weight:600}
    ul{list-style:none;margin:0;padding:0;display:flex;flex-direction:column;gap:8px}
    li{display:flex;align-items:center;gap:10px;background:var(--card);border:1px solid var(--line);border-radius:10px;padding:10px 14px}
    li label{display:flex;align-items:center;gap:10px;flex:1;cursor:pointer}
    li.done span{text-decoration:line-through;color:var(--dim)}
    li button{border:none;background:none;color:var(--dim);font-size:20px;line-height:1}
    """
    private static func todoBody(_ l: Lang) -> String {
        l.t("""
          <div class="app">
            <h1>待办清单</h1>
            <p class="sub">还有 <b id="count">0</b> 件未完成 · 自动保存在本地</p>
            <form id="form"><input id="input" type="text" placeholder="加一件要做的事…" autocomplete="off"><button>添加</button></form>
            <ul id="list"></ul>
          </div>
        """, """
          <div class="app">
            <h1>To-do</h1>
            <p class="sub"><b id="count">0</b> left · saved locally</p>
            <form id="form"><input id="input" type="text" placeholder="Add a task…" autocomplete="off"><button>Add</button></form>
            <ul id="list"></ul>
          </div>
        """)
    }
    private static let todoJS = """
    const KEY='todos',$=s=>document.querySelector(s);
    let todos=JSON.parse(localStorage.getItem(KEY)||'[]');
    const save=()=>localStorage.setItem(KEY,JSON.stringify(todos));
    function render(){const ul=$('#list');ul.innerHTML='';todos.forEach((t,i)=>{const li=document.createElement('li');if(t.done)li.className='done';const lab=document.createElement('label');const cb=document.createElement('input');cb.type='checkbox';cb.checked=t.done;cb.onchange=()=>{t.done=!t.done;save();render()};const sp=document.createElement('span');sp.textContent=t.text;lab.append(cb,sp);const del=document.createElement('button');del.textContent='×';del.onclick=()=>{todos.splice(i,1);save();render()};li.append(lab,del);ul.appendChild(li)});$('#count').textContent=todos.filter(t=>!t.done).length}
    $('#form').onsubmit=e=>{e.preventDefault();const v=$('#input').value.trim();if(!v)return;todos.push({text:v,done:false});$('#input').value='';save();render()};
    render();
    """

    // MARK: - landing
    private static let landingCSS = """
    .hero{text-align:center;padding:96px 24px 64px;background:radial-gradient(800px 400px at 50% -10%,#fff3e6,transparent)}
    .hero h1{font-size:48px;margin:0 0 14px;letter-spacing:-1px}
    .hero p{font-size:20px;color:var(--dim);max-width:560px;margin:0 auto 28px}
    .cta{display:inline-block;background:var(--accent);color:#fff;font-weight:700;padding:14px 32px;border-radius:12px;font-size:17px}
    .feat{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:18px;max-width:960px;margin:48px auto;padding:0 24px}
    .feat div{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:24px}
    .feat h3{margin:0 0 6px;font-size:18px}
    .feat p{margin:0;color:var(--dim);font-size:15px}
    """
    private static func landingBody(_ l: Lang) -> String {
        l.t("""
          <section class="hero">
            <h1>一句话讲清你的产品</h1>
            <p>用一行副标题说明它为谁解决什么问题。</p>
            <a class="cta" href="#">立即开始</a>
          </section>
          <section class="feat">
            <div><h3>✨ 卖点一</h3><p>用一两句话说明这个好处。</p></div>
            <div><h3>⚡ 卖点二</h3><p>用一两句话说明这个好处。</p></div>
            <div><h3>🔒 卖点三</h3><p>用一两句话说明这个好处。</p></div>
          </section>
        """, """
          <section class="hero">
            <h1>Your product in one line</h1>
            <p>A subheadline saying who it's for and what it solves.</p>
            <a class="cta" href="#">Get started</a>
          </section>
          <section class="feat">
            <div><h3>✨ Benefit 1</h3><p>A sentence or two about this benefit.</p></div>
            <div><h3>⚡ Benefit 2</h3><p>A sentence or two about this benefit.</p></div>
            <div><h3>🔒 Benefit 3</h3><p>A sentence or two about this benefit.</p></div>
          </section>
        """)
    }

    // MARK: - game
    private static let gameCSS = """
    .game{max-width:440px;margin:80px auto;padding:36px;text-align:center;background:var(--card);border:1px solid var(--line);border-radius:18px;box-shadow:0 20px 50px rgba(0,0,0,.06)}
    .game h1{margin:0 0 8px}
    #msg{font-size:20px;min-height:30px;margin:18px 0}
    form{display:flex;gap:8px;justify-content:center}
    input{width:130px;padding:12px;border:1px solid var(--line);border-radius:10px;font-size:18px;text-align:center}
    form button,#new{padding:12px 20px;border:none;border-radius:10px;background:var(--accent);color:#fff;font-weight:700}
    #new{display:none;margin-top:16px}
    .meta{color:var(--dim);margin-top:14px}
    """
    private static func gameBody(_ l: Lang) -> String {
        l.t("""
          <div class="game">
            <h1>🎯 猜数字</h1>
            <div id="msg">我想好了一个 1–100 的数字，猜猜看</div>
            <form id="form"><input id="input" type="number" min="1" max="100" placeholder="1-100"><button>猜</button></form>
            <button id="new">再玩一局</button>
            <div class="meta">已猜 <b id="tries">0</b> 次</div>
          </div>
        """, """
          <div class="game">
            <h1>🎯 Guess the Number</h1>
            <div id="msg">I'm thinking of a number from 1–100. Guess!</div>
            <form id="form"><input id="input" type="number" min="1" max="100" placeholder="1-100"><button>Guess</button></form>
            <button id="new">Play again</button>
            <div class="meta"><b id="tries">0</b> guesses</div>
          </div>
        """)
    }
    private static func gameJS(_ l: Lang) -> String {
        let hi = l.t("'再大一点 ↑'", "'Higher ↑'")
        let lo = l.t("'再小一点 ↓'", "'Lower ↓'")
        let win = l.t("'🎉 猜对了！用了 '+tries+' 次'", "'🎉 Correct! In '+tries+' tries'")
        let reset = l.t("'我想好了一个 1–100 的数字，猜猜看'", "\"I'm thinking of a number from 1–100. Guess!\"")
        return """
        let target=Math.floor(Math.random()*100)+1,tries=0;const $=s=>document.querySelector(s);
        $('#form').onsubmit=e=>{e.preventDefault();const g=parseInt($('#input').value);if(!g)return;tries++;let m;if(g===target){m=\(win);$('#new').style.display='inline-block'}else m=g<target?\(hi):\(lo);$('#msg').textContent=m;$('#tries').textContent=tries;$('#input').value='';$('#input').focus()};
        $('#new').onclick=()=>{target=Math.floor(Math.random()*100)+1;tries=0;$('#msg').textContent=\(reset);$('#tries').textContent=0;$('#new').style.display='none'};
        """
    }

    // MARK: - dashboard
    private static let dashCSS = """
    .dash{max-width:920px;margin:40px auto;padding:0 24px}
    h1{margin:0 0 20px}
    .cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:14px;margin-bottom:22px}
    .cards div{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:18px}
    .cards .n{font-size:30px;font-weight:800}
    .cards .k{color:var(--dim);font-size:13px}
    .chart-wrap{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:18px}
    canvas{width:100%;height:300px;display:block}
    """
    private static func dashBody(_ l: Lang) -> String {
        l.t("""
          <div class="dash">
            <h1>数据看板</h1>
            <div class="cards">
              <div><div class="n">1,280</div><div class="k">访问量</div></div>
              <div><div class="n">324</div><div class="k">新增用户</div></div>
              <div><div class="n">¥8.6k</div><div class="k">收入</div></div>
              <div><div class="n">98%</div><div class="k">满意度</div></div>
            </div>
            <div class="chart-wrap"><canvas id="chart"></canvas></div>
          </div>
        """, """
          <div class="dash">
            <h1>Dashboard</h1>
            <div class="cards">
              <div><div class="n">1,280</div><div class="k">Visits</div></div>
              <div><div class="n">324</div><div class="k">New users</div></div>
              <div><div class="n">$8.6k</div><div class="k">Revenue</div></div>
              <div><div class="n">98%</div><div class="k">Satisfaction</div></div>
            </div>
            <div class="chart-wrap"><canvas id="chart"></canvas></div>
          </div>
        """)
    }
    private static let dashJS = """
    const data=[40,65,52,78,90,61,84];const c=document.getElementById('chart'),x=c.getContext('2d');
    function draw(){const w=c.width=c.clientWidth*2,h=c.height=600;x.clearRect(0,0,w,h);const max=Math.max(...data),pad=40,bw=(w-pad*2)/data.length;data.forEach((v,i)=>{const bh=(v/max)*(h-pad*2),bx=pad+i*bw+bw*0.18,by=h-pad-bh;x.fillStyle='#ff8a3d';x.beginPath();x.roundRect?x.roundRect(bx,by,bw*0.64,bh,8):x.rect(bx,by,bw*0.64,bh);x.fill();x.fillStyle='#697086';x.font='22px sans-serif';x.textAlign='center';x.fillText(v,bx+bw*0.32,by-12)})}
    draw();window.addEventListener('resize',draw);
    """

    // MARK: - Vite + React (multi-file)
    private static func viteReactFiles(_ l: Lang) -> [ProjectFiles.ParsedFile] {
        [
            page("package.json", """
            {
              "name": "vite-react-app",
              "private": true,
              "type": "module",
              "scripts": { "dev": "vite", "build": "vite build", "preview": "vite preview" },
              "dependencies": { "react": "^18.3.1", "react-dom": "^18.3.1" },
              "devDependencies": { "@vitejs/plugin-react": "^4.3.1", "vite": "^5.4.0" }
            }
            """),
            page("vite.config.js", """
            import { defineConfig } from 'vite'
            import react from '@vitejs/plugin-react'
            export default defineConfig({ plugins: [react()] })
            """),
            page("index.html", """
            <!doctype html>
            <html lang="\(l == .zh ? "zh-CN" : "en")">
              <head>
                <meta charset="UTF-8" />
                <meta name="viewport" content="width=device-width, initial-scale=1.0" />
                <title>\(l.t("React 应用", "React App"))</title>
              </head>
              <body>
                <div id="root"></div>
                <script type="module" src="/src/main.jsx"></script>
              </body>
            </html>
            """),
            page("src/main.jsx", """
            import React from 'react'
            import { createRoot } from 'react-dom/client'
            import App from './App.jsx'
            import './index.css'
            createRoot(document.getElementById('root')).render(<App />)
            """),
            page("src/App.jsx", l.t("""
            import { useState } from 'react'
            export default function App() {
              const [count, setCount] = useState(0)
              return (
                <main className="app">
                  <h1>Vite + React</h1>
                  <p>一个最小的起步工程,改起来即时热重载。</p>
                  <button onClick={() => setCount(c => c + 1)}>点了 {count} 次</button>
                  <p className="hint">编辑 <code>src/App.jsx</code> 试试。</p>
                </main>
              )
            }
            """, """
            import { useState } from 'react'
            export default function App() {
              const [count, setCount] = useState(0)
              return (
                <main className="app">
                  <h1>Vite + React</h1>
                  <p>A minimal starter with instant HMR.</p>
                  <button onClick={() => setCount(c => c + 1)}>clicked {count} times</button>
                  <p className="hint">Edit <code>src/App.jsx</code> to try it.</p>
                </main>
              )
            }
            """)),
            page("src/index.css", """
            :root { color-scheme: light dark; }
            * { box-sizing: border-box; }
            body { margin: 0; min-height: 100vh; display: grid; place-items: center;
              font-family: -apple-system, system-ui, "PingFang SC", sans-serif; background: #f6f7f9; color: #1b2230; }
            .app { text-align: center; padding: 40px; }
            .app h1 { font-size: 40px; margin: 0 0 8px; }
            .app p { color: #697086; margin: 6px 0; }
            button { margin-top: 14px; padding: 12px 24px; border: none; border-radius: 10px;
              background: #4a7cff; color: #fff; font: inherit; font-weight: 600; cursor: pointer; }
            .hint { font-size: 13px; }
            code { background: #e7e9f0; padding: 2px 6px; border-radius: 5px; }
            """),
        ]
    }
}
