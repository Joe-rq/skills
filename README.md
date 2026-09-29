# My Claude Skills

个人在用的 [Claude Skills](https://support.claude.com/en/articles/12512176-what-are-skills) 集合，用于扩展 Claude 在特定领域的专业能力。

## Skills 列表

| Skill | 描述 | 语言 | 亮点 |
|-------|------|------|------|
| **adaptive-team-research** | 自适应多智能体研究团队：三种协作模式 × 三轮工作流（事实→辩论→共识） | 中文 | ✅ 三模式自动选择（集中/领域主导/对等）<br>✅ 结构化事实→辩论→共识工作流<br>✅ 投票矩阵 + Critic 升级机制<br>✅ 评测驱动优化（delta +87.5%） |
| **product-opportunity-research** | 多智能体产品机会深度研究：6 Agent 独立分析→交叉质询→总控裁决，产出机会地图+路线图+商业打包策略 | 中文 | ✅ 6 专业 Agent 并行<br>✅ 11 维量化评分<br>✅ 三圈交集优先级<br>✅ 0-36 月产品路线图 |
| **git-collaboration** | Git 协作工作流专家技能，覆盖 Fork + Feature Branch + Pull Request 模式 | 中文 | ✅ Fork + Feature Branch + PR 标准流程<br>✅ 7 步标准工作流 + 提交规范<br>✅ 7 个常见问题速查<br>✅ 分支管理 + 协作最佳实践 |
| **mermaid-ascii-renderer** | beautiful-mermaid ASCII/Unicode 渲染系统完整指南 | 中文 | ✅ 支持 5 种图表类型<br>✅ 详细的 API 文档<br>✅ 故障排查决策树<br>✅ 扩展开发指南 |
| **ppt-methodology-coach** | PPT 内容优先方法论：先内容后设计的六阶段引导式工作流 | 中文 | ✅ 六阶段递进（定目的→文字稿→定风格→素材→输出）<br>✅ 理解型/说服型二分 + 结构风格对照<br>✅ 每阶段退出标准与用户确认门禁<br>✅ 附三审检查清单 |

## 快速开始

### 安装 Skills

**方式一：`npx skills` 安装（推荐）**

```bash
# 安装全部 skills
npx skills add joe/skills --skill '*'

# 或安装指定 skill
npx skills add joe/skills --skill product-opportunity-research
npx skills add joe/skills --skill adaptive-team-research
npx skills add joe/skills --skill mermaid-ascii-renderer
npx skills add joe/skills --skill ppt-methodology-coach
```

**方式二：42plugin 安装**

```bash
42plugin install joe/joe/product-opportunity-research
```

**方式三：手动安装**

将对应 skill 目录复制到 Claude Desktop 的 skills 目录：

```bash
# macOS/Linux
cp -r <skill-name> ~/.claude/skills/

# Windows
xcopy <skill-name> %USERPROFILE%\.claude\skills\ /E /I
```

### 验证安装

重启 Claude Desktop 后，在对话中触发 skill：

- 测试 `mermaid-ascii-renderer`: "怎么用 beautiful-mermaid 生成 ASCII 图表？"
- 测试 `adaptive-team-research`: "帮我多角度分析一下这个设计方案"
- 测试 `product-opportunity-research`: "帮我做一个深度研究，主题是智能家居安全产品的市场机会"
- 测试 `git-collaboration`: "帮我创建一个功能分支并提交代码"
- 测试 `ppt-methodology-coach`: "帮我做一个关于 AI 编程助手的内部培训 PPT"

## 项目结构

```
skills/
├── <skill-name>/              # 每个 skill 独立目录
│   ├── SKILL.md              # 技能主体文档（必需）
│   ├── README.md             # 目录导航（可选）
│   ├── references/           # 详细参考文档（可选）
│   │   ├── core-systems.md
│   │   ├── diagrams.md
│   │   └── ...
│   └── assets/               # 资源文件（可选）
├── README.md                 # 本文件
└── .gitignore               # Git 忽略配置
```

## Skill 开发规范

### 文档结构

每个 skill 应包含清晰的渐进式披露结构：

1. **SKILL.md** - 核心入口（<5k 字）
   - 快速开始
   - 核心 API
   - 何时阅读参考文档

2. **references/** - 详细参考（按需加载）
   - 实现细节
   - 故障排查
   - 扩展指南

### 命名规范

- Skill 目录名：kebab-case（如 `mermaid-ascii-renderer`）
- Frontmatter name：与目录名一致
- 版本号：语义化版本（如 `1.0.0`）

## 最近更新

| 日期 | Skill | 更新内容 |
|------|-------|---------|
| 2026-09-29 | ppt-methodology-coach | v1.0.0 新增：先内容后设计的六阶段 PPT 引导工作流 |
| 2026-07-07 | git-collaboration | v1.0.0 新增：Fork + Feature Branch + Pull Request 协作工作流技能 |
| 2026-03-18 | 全局 | 仓库重命名：my-claude-skills → skills，支持 `npx skills add joe/skills` 安装 |
| 2026-03-13 | adaptive-team-research | v1.3.1 评测驱动优化：canvas 创建强制约束、行动计划负责角色必填、用户确认强制门禁 |
| 2026-03-18 | product-opportunity-research | v1.0.1 发布：6 Agent 交叉质询框架 + 11 维评分 + 机会地图 + 0-36月路线图 |
| 2026-02-27 | product-opportunity-research | 新增：6 Agent 多智能体产品机会深度研究框架 |
| 2026-02-18 | 全局 | 项目审查优化：重命名 skills.md→SKILL.md、agent-skills-doc→docs/、README 增加语言列、frontmatter 标准化 |
| 2026-02-18 | adaptive-team-research | 合并 multi-perspective-review 到 adaptive-team-research，三种模式做实差异化 |
| 2026-01-30 | mermaid-ascii-renderer | 全面优化：范围与限制、API 细节、多图示例、故障决策树、扩展指南 |
| 2026-01-30 | 全局 | 添加 .gitignore，忽略依赖和构建文件 |

## 贡献指南

欢迎提交改进：

1. Fork 本仓库
2. 创建 feature 分支
3. 提交更改（遵循现有 commit 风格）
4. 发起 Pull Request

### Commit 风格

```
<类型>: <描述>

docs: 更新文档
feat: 新增功能
fix: 修复问题
chore: 维护任务
```

## 相关资源

- [Claude Skills 官方文档](https://support.claude.com/en/articles/12512176-what-are-skills)
- [beautiful-mermaid](https://github.com/lukilabs/beautiful-mermaid) - mermaid-ascii-renderer 基于的开源项目

## License

MIT

---

**维护者**: Joe  
**创建时间**: 2024-12  
**最后更新**: 2026-09-29
