# Claude Code RStudio Integration - Task Specifications

This directory contains detailed task specifications for implementing and improving Claude Code integration in RStudio.

## Quick Overview

| Task | Priority | Complexity | Timeline | Status |
|------|----------|-----------|----------|---------|
| [SDK Feature Parity](./sdk-feature-parity/spec.md) | **HIGH** | HIGH | 8-11 weeks | Recommended |
| [UI Improvements](./ui-improvements/spec.md) | **HIGH** | MEDIUM | 2-3 weeks | Recommended |
| [ACP+WebSocket](./acp-websocket-integration/spec.md) | MEDIUM | MEDIUM | 1.5-2 weeks | Experimental |

## Task Descriptions

### 1. SDK Feature Parity
**Path**: `./sdk-feature-parity/spec.md`

Expand current Claude Agent SDK implementation from ~15% to 100% coverage of BASIC and INTERMEDIATE features.

**Key Features**:
- Tool control (allowed/disallowed tools)
- Model selection
- System prompts
- Multi-session support
- Session persistence
- Cost/usage tracking
- Advanced streaming

**Recommended For**:
- Production use
- Maximum stability
- Official SDK support
- Advanced features (hooks, custom tools)

**Dependencies**: Python 3.10+, Claude Agent SDK

---

### 2. UI Improvements
**Path**: `./ui-improvements/spec.md`

Solve console blocking and add R-specific features for better UX.

**Key Features**:
- Console never blocks (browserViewer or background process)
- Quick query function: `claude("explain this")`
- Environment snapshot integration
- Plot capture and analysis
- Configurable viewer modes

**Recommended For**:
- All users
- Better R workflow integration
- Quick wins (browserViewer = 1 line change)

**Dependencies**: None (works with any backend)

**Quick Win**: Change `paneViewer()` to `browserViewer()` = console blocking solved immediately!

---

### 3. ACP + WebSocket Integration
**Path**: `./acp-websocket-integration/spec.md`

Alternative architecture using Agent Client Protocol via WebSocket proxy.

**Key Features**:
- Multi-agent support (Claude, Gemini, GitHub, custom)
- Simpler architecture (no Python server)
- WebSocket async (no blocking)
- Open ecosystem (ACP growing)

**Recommended For**:
- Multi-agent flexibility
- Simpler deployment
- Future-proofing
- Community-driven features

**Dependencies**: Node.js, websocketd (or mcp2websocket)

**Trade-offs**:
- ✅ Multi-agent support
- ✅ Less code (~200 vs ~500 lines)
- ❌ Lose SDK-specific features
- ❌ Beta-level protocol stability

---

## Recommended Implementation Path

### Path A: Production (Recommended)
1. **Week 1-2**: UI Improvements (Phase 1-2) - Quick wins
2. **Week 3-12**: SDK Feature Parity - Full implementation
3. **Week 13+**: Advanced SDK features as needed

**Result**: Stable, feature-rich, Claude-focused integration

---

### Path B: Experimental (Alternative)
1. **Week 1**: UI Improvements (Phase 1-2) - Quick wins
2. **Week 2-3**: ACP+WebSocket prototype
3. **Week 4**: Evaluate ACP vs SDK
4. **Week 5+**: Choose best approach, complete implementation

**Result**: Multi-agent flexibility, simpler architecture

---

### Path C: Hybrid (Best of Both)
1. **Week 1-2**: UI Improvements
2. **Week 3-4**: ACP+WebSocket MVP
3. **Week 5-12**: SDK Feature Parity
4. **Week 13+**: Ship both, let users choose

**Result**: Maximum flexibility, choose at runtime

---

## Parallelization Opportunities

### Multiple Developers (4 optimal)

**Developer 1**: UI Improvements
- browserViewer
- REPL function
- Environment/Plot integration

**Developer 2-4**: SDK Feature Parity (parallel git worktrees)
- Developer 2: Configuration features
- Developer 3: Session management
- Developer 4: Messages & errors

**Result**: All tasks complete in ~8-10 weeks

### Single Developer

**Weeks 1-2**: UI Improvements (high impact, quick)
**Weeks 3-12**: SDK Feature Parity (sequential)
**Week 13+**: Polish and docs

**Result**: Fully featured in ~3 months

---

## Decision Matrix

Choose your path based on priorities:

| Priority | Recommended Path |
|----------|-----------------|
| **Stability first** | Path A (SDK focus) |
| **Innovation first** | Path B (ACP experiment) |
| **Flexibility first** | Path C (Both) |
| **Quick wins first** | UI Improvements (all paths) |
| **Multi-agent required** | Path B or C (ACP) |
| **Claude only** | Path A (SDK) |

---

## Getting Started

### Step 1: Choose Your Path
Review the three task specs and decide which approach fits your needs.

### Step 2: UI Quick Win
Regardless of path chosen, start with UI Improvements Phase 1-2:
- Change to `browserViewer()` (1 line)
- Implement `claude()` REPL function (1 day)

**Impact**: Immediate UX improvement, unblocks users

### Step 3: Backend Implementation
Choose SDK Feature Parity OR ACP+WebSocket and begin implementation.

### Step 4: Iterate
Gather user feedback, iterate on UX, add features based on real usage.

---

## Success Metrics

### Technical
- ✅ All tests passing (unit + integration)
- ✅ No console blocking
- ✅ No crashes or hangs
- ✅ Performance acceptable (< 100ms latency)
- ✅ Code coverage > 80%

### User Experience
- ✅ Natural R workflow integration
- ✅ Clear documentation
- ✅ Helpful error messages
- ✅ Positive user feedback
- ✅ Active usage in real projects

---

## Questions?

For detailed implementation guidance, see individual task spec.md files:
- `sdk-feature-parity/spec.md`
- `ui-improvements/spec.md`
- `acp-websocket-integration/spec.md`

Each spec includes:
- Detailed implementation steps
- Code examples
- Timeline estimates
- Testing requirements
- Risk assessment
- Success criteria
