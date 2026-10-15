// Static translation only. No tracking, API requests, storage, or credentials.
const english = {
  "skip": "Skip to content",
  "navSetup": "How to use it",
  "navPrinciple": "How it works",
  "eyebrow": "FOR THE HERMES / OPENCLAW YOU ALREADY USE",
  "headline1": "Your agent stays home.",
  "headline2": "Take access with you.",
  "intro": "Open Hermland on another Mac and keep using your agent at home. Your models, memory, and conversations stay in place. No second setup for your models.",
  "downloadHero": "Download for Mac",
  "seeFlow": "See what you need first ↓",
  "platform": "0.2.0 Beta · macOS 14+ · Apple Silicon / Intel",
  "signed": "Signed and Apple-notarized · Free and open source",
  "welcomeAlt": "Native Hermland welcome screen: select Hermes or OpenClaw, start connecting, or import an existing connection file. The app UI is in Chinese.",
  "previewCaption": "Native 0.2.0 interface preview. Choose the agent you already use; you are not installing another agent.",
  "beforeEyebrow": "BEFORE YOU START",
  "beforeTitle": "Three roles. One familiar agent.",
  "beforeIntro": "Hermland connects to your agent; it does not host one. You need these for first setup. Later, opening the app reconnects with your saved configuration.",
  "role1Label": "Your home Mac",
  "role1Title": "Where the agent runs",
  "role1Body": "Your existing Hermes + WebUI, or OpenClaw Gateway + Control UI. Keep this Mac online, logged in, and awake.",
  "role2Label": "Your cloud server · VPS",
  "role2Title": "Connects the two Macs",
  "role2Body": "Your own Debian / Ubuntu server, managed by someone you trust. No domain name or inbound port on your home router is needed.",
  "role3Label": "The Mac you take with you",
  "role3Title": "Where you open Hermland",
  "role3Body": "macOS 14 or later. Install only Hermland here, not another Hermes / OpenClaw. No need to enter model API keys again.",
  "serverTitle": "No VPS yet? Start here",
  "serverExplain": "A VPS is a cloud server you rent and pay the provider for. It relays connections; your agent does not move there.",
  "server1": "Create a Debian / Ubuntu server with a provider you trust. Note its public IP and SSH port, usually 22.",
  "server2": "Verify its identity through the provider console, then confirm that you or your administrator can log in over SSH. Ask a trusted person to help if this is unfamiliar.",
  "server3": "Enter the IP and port in the app. Your existing agent can then help configure the relay. Entering an address does not install software or authorize a device.",
  "serverGuide": "Open the server preparation guide (Chinese) ↗",
  "serverAlt": "Native server preparation screen: choose an existing server or the no-server path, then enter its address and SSH port. Chinese UI.",
  "serverCaption": "Native interface preview: address and port only. No administrator password is collected.",
  "setupEyebrow": "YOUR FIRST CONNECTION",
  "setupTitle": "Your agent helps set up. You approve access.",
  "setupIntro": "Use the conversation where you already talk to Hermes / OpenClaw. With execution tools, it can help configure the relay. Otherwise, you or your administrator follows the manual guide.",
  "step1Title": "Open the app. Enter your server.",
  "step1Body": "On the Mac you take with you, select your existing agent and click “开始连接” (start connecting). Enter your VPS address and SSH port. Confirm that you or your administrator can already log in through a verified connection.",
  "step1Check": "Done when: the server is ready. If not, use the VPS guide above first.",
  "step2Title": "Send a card. Check and approve.",
  "step2Body": "Click “复制连接卡” (copy connection card) and paste it into your usual agent conversation. It includes this Mac’s public key and setup instructions. Check the reported device name and key fingerprint before explicitly approving access. First setup also requires checking the home Mac’s relay key.",
  "step2Check": "Done when: you receive a .json connection file. No execution tools? Use “查看手动方式” (manual setup) in the app.",
  "step3Title": "Import the file. Check the connection.",
  "step3Body": "Save the file on this Mac. Click “我收到连接文件了” (I have the connection file) and select it. Check its trusted source and server fingerprint before connecting. Once the four checks pass, complete the original web login and send a message to verify a real response.",
  "step3Check": "Done when: your original chats are visible and the agent answers. Health checks send no model messages.",
  "manual": "Prefer to do it yourself? Commands and pass criteria (Chinese) ↗",
  "dailyTitle": "For everyday use",
  "dailyBody": "Open Hermland. It reconnects with the saved configuration. Keep the home Mac and relay server online.",
  "addTitle": "For another Mac",
  "addBody": "Choose “其他设备已连好？新增这台 Mac” (add this Mac). Authorize only the new computer, without reinstalling your agent or server. An existing connection file can be imported directly.",
  "principleEyebrow": "HOW IT WORKS",
  "principleTitle": "The same agent at home. A new way to reach it.",
  "principleIntro": "Each Mac initiates its own connection to your VPS. Hermland uses this route to display your original agent’s web interface. It does not take over your models or migrate your chats.",
  "client": "Your client Mac",
  "clientNote": "Use the original web interface",
  "vps": "Your VPS",
  "relay": "Relays connections",
  "relayNote": "Your agent does not move here",
  "home": "Your home Mac",
  "homeNote": "Models, memory, and chats stay here",
  "arrowNote": "Arrows show connection initiation; messages travel both ways. Only SSH needs an internet-facing entry, not your agent’s web port.",
  "trustTitle": "An address is not permission",
  "trustBody": "Each computer has its own keys. The private key stays in local Keychain. An administrator registers only public keys you explicitly approve, and the app verifies the server’s identity. Knowing the IP or having a connection file does not grant access.",
  "boundaryTitle": "The trust boundary is explicit",
  "boundary": "Trust the VPS administrator: two SSH hops are not end-to-end encryption between the Macs. Keep your agent’s original login enabled. Other local programs can access the local port opened by the app.",
  "panoramaTitle": "Expand the illustrated feature overview",
  "panoramaAlt": "Chinese conceptual overview of Hermland features, including manual key approval, connection checks, and device revocation. Not a software screenshot.",
  "artCaption": "A conceptual feature illustration, not a software screenshot. Follow the app and the steps above for actual setup.",
  "downloadEyebrow": "READY WHEN YOU ARE",
  "downloadTitle": "Take access with you.",
  "releasePlatform": "Hermland 0.2.0 Beta · macOS 14+ · Apple Silicon / Intel",
  "downloadZip": "Download Mac ZIP ↗",
  "installTitle": "After downloading",
  "install1": "Quit the old Hermland before upgrading.",
  "install2": "Unzip the file and move Hermland to Applications.",
  "install3": "Open the app and follow the first-connection steps above.",
  "toolkit": "The setup toolkit is included. Download only this app; no separate toolkit is needed.",
  "releaseWarning": "Developer ID signing, Apple notarization, and Gatekeeper checks passed. Still a beta: independent first-time-user and Intel hardware acceptance are pending. iOS is not available to download yet.",
  "releaseNotes": "Release notes and checksums ↗",
  "installHelp": "Trouble installing? ↗",
  "faqTitle": "A few things you may wonder",
  "vpnTitle": "Why not use Tailscale / a VPN?",
  "vpnBody": "Hermland focuses on one agent web interface, reusing your VPS and built-in Mac SSH without joining another VPN network. You maintain the server, and first setup is not necessarily easier than Tailscale. This is not a claim of stronger security: Tailscale also offers device approval and access rules, and its DERP relays cannot decrypt end-to-end encrypted traffic. Our VPS administrator must be trusted. If you already use Tailscale or need several services, keep it. This app has no Tailscale mode and does not change your VPN.",
  "comparison": "Compare six remote-access options ↗",
  "faq1Title": "What if my home Mac is asleep or off?",
  "faq1Body": "Bring it online, log in, and keep it awake first. Hermland cannot wake a powered-off Mac. This setup path requires the agent to run on a Mac; a Linux agent host is not supported in this version.",
  "faq2Title": "Checks pass, but the agent does not answer?",
  "faq2Body": "The four checks verify configuration, device keys, SSH, and backend health, not the model. Complete the original web login and send a test message. Your original agent still manages model accounts, quotas, and conversations.",
  "faq3Title": "Can I revoke just one lost computer?",
  "faq3Body": "Yes. An administrator revokes its public key over trusted SSH. Active connections close and new ones are rejected, without deleting chats or affecting other devices. Management is currently command-line only; there is no management UI.",
  "revokeGuide": "Authorization and revocation guide (Chinese) ↗",
  "faq4Title": "Do I need Screen Recording permission or autossh?",
  "faq4Body": "Hermland needs neither Screen Recording nor Accessibility permission. Permissions for your agent’s desktop tools are separate. New relays use built-in macOS launchd and SSH, without an autossh install. Existing services stay unchanged.",
  "faq5Title": "What about macOS security or Keychain prompts?",
  "faq5Body": "A normal first-launch confirmation is expected. For Keychain access, verify Hermland and approve it yourself; do not delete the device key. If macOS reports an unverified developer, check the download source, version, and checksum, then report it. Do not disable Gatekeeper or run protection-removal scripts.",
  "apple": "Apple’s safe-launch guidance ↗",
  "faq6Title": "Do you receive my public keys or chats?",
  "faq6Body": "This is a static site with no accounts, forms, authorization requests, chat backend, or analytics scripts. GitHub hosts browsing and downloads. The app reaches your home agent through your VPS, not through our chat service.",
  "footer": "Connect to the agent you already use. The app and detailed manual guides currently use Chinese. No claim of an independent security audit.",
  "privacy": "Privacy",
  "security": "Security and feedback ↗"
};

if (new URLSearchParams(location.search).get("lang") === "en") {
  document.documentElement.lang = "en";
  document.title = "Hermland — Take your agent access with you";
  document.querySelector('meta[name="description"]').content = "Reach your existing Hermes or OpenClaw at home from another Mac. See the native app, server requirements, and first-connection steps. Keep your models and chats in place.";
  document.querySelectorAll("[data-i18n]").forEach(node => {
    node.textContent = english[node.dataset.i18n];
  });
  document.querySelectorAll("[data-i18n-alt]").forEach(node => {
    node.alt = english[node.dataset.i18nAlt];
  });
  document.querySelectorAll("[data-en-href]").forEach(node => {
    node.href = node.dataset.enHref;
  });
  const language = document.getElementById("language");
  language.href = "./";
  language.lang = "zh-CN";
  language.textContent = "中文";
  language.setAttribute("aria-label", "阅读中文版");
  document.querySelector("nav").setAttribute("aria-label", "Navigation");
  document.querySelector(".network").setAttribute("aria-label", "Both Macs initiate SSH connections to your VPS");
}
