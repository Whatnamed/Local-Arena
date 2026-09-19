export type ThirdPartyProject = {
  name: string;
  version?: string;
  license: string;
  url: string;
  description: string;
  descriptionZh: string;
};

export type ThirdPartyGroup = {
  id: "game" | "panel" | "build" | "data";
  title: string;
  titleZh: string;
  projects: ThirdPartyProject[];
};

export const THIRD_PARTY_GROUPS: ThirdPartyGroup[] = [
  {
    id: "game",
    title: "Game runtime and provenance",
    titleZh: "游戏运行栈与来源",
    projects: [
      {
        name: "Local Arena",
        version: "v1.4.3 source base",
        license: "AGPL-3.0",
        url: "https://github.com/numakkiyu/Local-Arena",
        description: "Repository, player-cosmetics plugin and Panel this product is built from.",
        descriptionZh: "本产品的仓库、玩家饰品插件与面板代码基底。",
      },
      {
        name: "CS2-Bot-Improver",
        version: "v1.4.2 source base",
        license: "AGPL-3.0",
        url: "https://github.com/ed0ard/CS2-Bot-Improver",
        description: "Upstream Local Arena itself derives from; kept for provenance only.",
        descriptionZh: "Local Arena 的上游来源，此处仅作为代码溯源保留。",
      },
      {
        name: "Metamod:Source",
        version: "2.0.0-git1406",
        license: "zlib/libpng",
        url: "https://github.com/alliedmodders/metamod-source",
        description: "Native Source engine plugin loader distributed with the managed payload.",
        descriptionZh: "随受管负载分发的 Source 引擎原生插件加载器。",
      },
      {
        name: "CounterStrikeSharp",
        version: "v1.0.371",
        license: "GPL-3.0 + MIT plugin exception",
        url: "https://github.com/roflmuffin/CounterStrikeSharp",
        description: "Managed CS2 plugin runtime. Published plugins may use the repository's MIT exception.",
        descriptionZh: "CS2 托管插件运行时；其许可证为 GPL-3.0，并为已发布插件提供 MIT 例外。",
      },
    ],
  },
  {
    id: "panel",
    title: "Panel runtime",
    titleZh: "面板运行时",
    projects: [
      {
        name: "Tauri and official plugins",
        version: "v2",
        license: "MIT OR Apache-2.0",
        url: "https://github.com/tauri-apps/tauri",
        description: "Desktop shell, IPC, dialogs, clipboard, opener, and single-instance support.",
        descriptionZh: "桌面外壳、IPC、对话框、剪贴板、外部打开与单实例支持。",
      },
      {
        name: "React / React DOM",
        version: "v18.3.1",
        license: "MIT",
        url: "https://github.com/facebook/react",
        description: "Panel component and rendering runtime.",
        descriptionZh: "面板组件与界面渲染运行时。",
      },
      {
        name: "Lucide React",
        version: "v1.24.0",
        license: "ISC",
        url: "https://github.com/lucide-icons/lucide",
        description: "Interface icon library.",
        descriptionZh: "面板使用的界面图标库。",
      },
      {
        name: "Inter",
        license: "SIL OFL-1.1",
        url: "https://github.com/rsms/inter",
        description: "Bundled variable user-interface typeface.",
        descriptionZh: "随面板打包的可变界面字体。",
      },
      {
        name: "Serde / serde_json",
        license: "MIT OR Apache-2.0",
        url: "https://github.com/serde-rs/serde",
        description: "Rust configuration and data serialization.",
        descriptionZh: "Rust 配置与结构化数据序列化。",
      },
      {
        name: "sha2 / base64",
        license: "MIT OR Apache-2.0",
        url: "https://github.com/RustCrypto/hashes",
        description: "Hashing and binary-text encoding utilities.",
        descriptionZh: "哈希校验与二进制文本编码工具。",
      },
      {
        name: "fs2",
        version: "v0.4",
        license: "MIT OR Apache-2.0",
        url: "https://github.com/danburkert/fs2-rs",
        description: "Portable file locking used by atomic storage operations.",
        descriptionZh: "原子存储操作使用的跨平台文件锁。",
      },
      {
        name: "sysinfo",
        version: "v0.33",
        license: "MIT",
        url: "https://github.com/GuillaumeGomez/sysinfo",
        description: "Process and system inspection used by safety checks.",
        descriptionZh: "安全检查使用的进程与系统信息读取库。",
      },
      {
        name: "zip",
        version: "v2.4",
        license: "MIT",
        url: "https://github.com/zip-rs/zip2",
        description: "ZIP archive support for diagnostics and updates.",
        descriptionZh: "诊断包与更新文件使用的 ZIP 归档支持。",
      },
      {
        name: "winreg / windows-sys",
        license: "MIT; MIT OR Apache-2.0",
        url: "https://github.com/microsoft/windows-rs",
        description: "Windows registry and operating-system API bindings.",
        descriptionZh: "Windows 注册表与系统 API 绑定。",
      },
    ],
  },
  {
    id: "build",
    title: "Build toolchain",
    titleZh: "构建工具链",
    projects: [
      {
        name: "TypeScript",
        version: "v5.6",
        license: "Apache-2.0",
        url: "https://github.com/microsoft/TypeScript",
        description: "Static typing and frontend compilation.",
        descriptionZh: "前端静态类型检查与编译工具。",
      },
      {
        name: "Vite / @vitejs/plugin-react",
        version: "v6",
        license: "MIT",
        url: "https://github.com/vitejs/vite",
        description: "Frontend development server and production bundler.",
        descriptionZh: "前端开发服务器与生产构建工具。",
      },
      {
        name: "Tauri CLI / tauri-build",
        version: "v2",
        license: "MIT OR Apache-2.0",
        url: "https://github.com/tauri-apps/tauri",
        description: "Desktop application build and packaging tools.",
        descriptionZh: "桌面应用构建与打包工具。",
      },
    ],
  },
  {
    id: "data",
    title: "Catalog and capability data",
    titleZh: "目录与能力数据",
    projects: [
      {
        name: "ByMykel/CSGO-API",
        version: "commit 342d496",
        license: "MIT",
        url: "https://github.com/ByMykel/CSGO-API",
        description: "Pinned sticker identifiers, localized names, and image metadata.",
        descriptionZh: "固定提交来源的贴纸 ID、本地化名称与图片元数据。",
      },
      {
        name: "Nereziel/cs2-WeaponPaints",
        license: "GPL-3.0",
        url: "https://github.com/Nereziel/cs2-WeaponPaints",
        description: "Source of the weapon skin images and the localized paint-kit name tables.",
        descriptionZh: "武器皮肤图片与各语言外观名称表的来源。",
      },
      {
        name: "SteamTracking/GameTracking-CS2",
        version: "commit 88d5684",
        license: "No repository license published",
        url: "https://github.com/SteamTracking/GameTracking-CS2",
        description: "Pinned factual schema reference used to constrain supported weapons; the repository publishes no license file.",
        descriptionZh: "用于限制支持武器范围的固定事实型 schema 参考；该仓库未发布许可证文件。",
      },
    ],
  },
];
