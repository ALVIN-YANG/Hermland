# Hermland 功能全景图

用途：GitHub README 首屏，让已有 Hermes / OpenClaw 用户知道产品用途、权限机制和首次接入步骤。

读者：已经有自己的 Agent，希望从另一台 Mac 继续使用原模型、记忆与会话。

制作：内置图像生成。用户提供的 Langfuse 图片仅作美术风格参考；不复制其品牌、功能或原角色。

视觉：明亮的玻璃工作室、蓝天绿植、日式赛璐璐动漫、小人物实际演示、深蓝标题与青绿色连线。一个完整空间中的六块大型展板，不把人物当成软件组件。

内容：原 Agent 与会话；双 SSH 通道；手动公钥授权；Agent 协助初始化；导入配置与检查；单设备撤销。下方四步条：初始化、发公钥、导入配置、连接验收。画面为原理示意，不冒充产品截图。

约束：不画管理 GUI、自动授权、云托管 Agent 或一键安装为已实现功能。不称端到端加密或零风险；VPS 是可信中转点。图中短标签对应 README 的可搜索文字与完整操作文档。

成图复核：用内置图像编辑移除生成器编造的终端命令和公钥字符串；改为人工核对、确认后授权和撤销结果。将健康检查的聊天示意改为“健康接口通过，请再验收模型回答”。保留准确标签与原构图。

## 生成提示词

Use case: infographic-diagram, illustrated product overview.
Asset type: one landscape panoramic GitHub README information graphic, roughly 3:2, very high resolution, clean readable Chinese typography.
Input image 1: STYLE REFERENCE ONLY. Create an original scene for Hermland; do not edit, copy Langfuse content, or reuse its characters.
Primary request: A bright Japanese cel-shaded anime studio panorama with small original people explaining the REAL Hermland remote-access product. Match the reference's sunny glass windows, sky, plants, warm wood, navy-blue headings, cyan accents, and lively but organized workstations. It is an information graphic, not just a decorative character cover.
Composition: large top sign; six large readable exhibit boards arranged in two rows of three, integrated into one open workshop. Original friendly chibi adult developers in casual clothes interact with computers, public-key cards, terminal sheets, and checklists. People occupy the lower foreground of each station and never obscure the text. Large bold navy headings, minimal short supporting copy. Diagrams, actors and actions explain the feature. Decorative props remain subordinate. Do not imitate a real screenshot; explicitly mark the illustration as a conceptual overview.
Text verbatim, title: "Hermland 功能全景". Subtitle: "从另一台 Mac，连接你自己的 Hermes / OpenClaw".
Panel 1 heading: "原 Agent 与会话". A home Mac Mini and familiar chat window, model/memory/history folders stay beside the Mini. Supporting label: "不迁移模型、记忆、会话".
Panel 2 heading: "双 SSH 通道". A clear simplified laptop—VPS—home Mac Mini conceptual connection, two separate cyan SSH links with locks; both Macs connect to the user's VPS. Labels: "客户端", "自己的 VPS", "常驻 Mac". Supporting label: "VPS 必须可信". No direct end-to-end encrypted laptop-to-Mini claim.
Panel 3 heading: "手动公钥授权". A person hands a PUBLIC KEY card to a human administrator who checks it; private key stays locked on the laptop, an unapproved laptop stays outside. Supporting label: "私钥留在本机". No automatic approval or connection request portal.
Panel 4 heading: "Agent 协助初始化". User copies an instruction and shares a tools/docs package with their ALREADY EXISTING Agent; the character consults a manual checklist. Small tags "Hermes" and "OpenClaw". Supporting label: "也可按说明手动完成". No server marketplace, purchasing UI, or one-click universal installer.
Panel 5 heading: "导入配置与检查". A native desktop client conceptual checklist with four rows labeled "配置", "密钥", "SSH", "健康" and green checkmarks; a human checks a separate chat result. Supporting label: "健康通过 ≠ 模型可用". Do not show a new chat engine or invented product controls.
Panel 6 heading: "单设备撤销". Administrator uses a terminal; one laptop's key card is crossed out red and its connection closes, while another authorized device and the Mini link remain green. Supporting label: "断开该设备，不动 Agent". Show terminal-based management, not a nonexistent management dashboard.
Bottom long sign: "1 初始化  →  2 发公钥  →  3 导入配置  →  4 连接验收".
Bottom small footer: "macOS 14+ · MIT · 开发预览 · 原理示意".
Constraints: readable exact Chinese short labels, no additional invented text or tiny paragraphs, no Langfuse text, no brand logos that were not provided, no security absolutes, no shared Gate token login, no public WebUI, no claims of automatic device authorization, no watermarks. The image must visibly answer what the app does, what features it has, and how a user starts.
