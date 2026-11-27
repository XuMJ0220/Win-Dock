"use strict";

const byId = (id) => document.getElementById(id);
const desktop = byId("desktop");
const dock = byId("dock");
const dockAnchor = byId("dock-anchor");
const screenEdge = byId("screen-edge");
const picker = byId("window-picker");
const magnify = byId("magnify");
const autoHide = byId("auto-hide");
const result = byId("result");
const iconSources = window.winDockIconSources ?? {};

const pinned = [
  {
    id: "explorer", name: "文件资源管理器", shortName: "文件", letter: "文", color: "#9a6f30",
    windows: [{ title: "Win-Dock 项目文件", lines: ["README.md", "GLOSSARY.md", "prototypes"] }],
  },
  {
    id: "edge", name: "Microsoft Edge", shortName: "Edge", letter: "E", color: "#198b8d",
    windows: [
      { title: "Win-Dock 规格地图", lines: ["首版规格", "显示规则 · 固定应用 · 交互原型"] },
      { title: "桌面设计参考", minimized: true, lines: ["窗口列表中的第二个示例窗口"] },
    ],
  },
  {
    id: "notepad", name: "记事本", shortName: "记事本", letter: "记", color: "#497fbb",
    windows: [{
      title: "试用笔记.txt",
      lines: ["移过几个图标，感受放大和相邻图标的反馈。", "点击 Edge，选一个要切回的窗口。", "左右拖动图标，试试调整顺序。"],
    }],
  },
  {
    id: "powershell", name: "PowerShell", shortName: "终端", letter: ">_", color: "#2a5989",
    windows: [{ title: "开发终端", lines: ["PS D:\\Win-Dock>", "程序坞交互原型"] }],
  },
  { id: "calculator", name: "计算器", shortName: "计算器", letter: "＋", color: "#42657a", windows: [] },
  { id: "settings", name: "设置", shortName: "设置", letter: "⚙", color: "#535e71", windows: [] },
];

const variants = [
  { key: "A", name: "连续托盘", layout: "tray", scale: 1.49, render: renderTray },
  { key: "B", name: "独立磁贴", layout: "tiles", scale: 1.31, render: renderTiles },
  { key: "C", name: "名称卡片", layout: "labels", scale: 1.18, render: renderLabels },
];

const initialKey = new URLSearchParams(location.search).get("variant")?.toUpperCase();
let variant = variants.find((item) => item.key === initialKey) ?? variants[0];
let active = { app: pinned[2], window: pinned[2].windows[0] };
let draggedApp = null;
let pickerButton = null;
let hideTimer;

function iconFor(app) {
  const icon = document.createElement(iconSources[app.id] ? "img" : "span");
  icon.className = "app-icon";
  icon.setAttribute("aria-hidden", "true");
  if (iconSources[app.id]) {
    icon.src = iconSources[app.id];
    icon.alt = "";
    icon.draggable = false;
  } else {
    icon.classList.add("fallback-icon");
    icon.style.setProperty("--fallback-color", app.color);
    icon.textContent = app.letter;
  }
  return icon;
}

function appButton(app, style) {
  const button = document.createElement("button");
  button.type = "button";
  button.className = "dock-app " + style;
  button.dataset.app = app.id;
  button.draggable = true;
  const windowCount = app.windows.length;
  button.setAttribute("aria-label", app.name + (windowCount ? "，" + windowCount + " 个可切回窗口" : "，打开应用"));
  if (windowCount > 1) button.setAttribute("aria-haspopup", "true");

  const face = style === "label-app" ? document.createElement("span") : button;
  face.append(iconFor(app));
  if (style === "label-app") {
    face.className = "label-face";
    const name = document.createElement("span");
    name.className = "app-name";
    name.textContent = app.shortName;
    face.append(name);
    button.append(face);
  } else {
    button.classList.add("icon-only");
    button.dataset.tooltip = app.name;
  }
  if (windowCount > 0) {
    const marker = document.createElement("span");
    marker.className = "app-running";
    marker.setAttribute("aria-hidden", "true");
    face.append(marker);
  }
  return button;
}

function renderTray() {
  const tray = document.createElement("div");
  tray.className = "continuous-tray";
  tray.append(...pinned.map((app) => appButton(app, "tray-app")));
  return tray;
}

function renderTiles() {
  const tiles = document.createDocumentFragment();
  tiles.append(...pinned.map((app) => appButton(app, "tile-app")));
  return tiles;
}

function renderLabels() {
  const cards = document.createDocumentFragment();
  cards.append(...pinned.map((app) => appButton(app, "label-app")));
  return cards;
}

function updateStatus(message) {
  const running = pinned.filter((app) => app.windows.length > 0).length;
  byId("dock-state").textContent = "固定 " + pinned.length + " 个应用 · " + running + " 个有可切回窗口";
  if (message) result.textContent = message;
}

function renderDock() {
  dock.className = "dock-layout " + variant.layout;
  dock.replaceChildren(variant.render());
  byId("variant-key").textContent = variant.key;
  byId("variant-name").textContent = variant.name;
  updateStatus();
}

function renderWindow() {
  const frame = byId("preview-window");
  frame.hidden = !active;
  if (!active) return;

  byId("preview-window-icon").replaceChildren(iconFor(active.app));
  byId("preview-window-title").textContent = active.window.title + " · " + active.app.name;
  byId("preview-document-title").textContent = active.window.title;
  const lines = active.window.lines.map((line) => {
    const paragraph = document.createElement("p");
    paragraph.textContent = line;
    return paragraph;
  });
  byId("preview-document-lines").replaceChildren(...lines);
}

function setDockVisible(visible) {
  clearTimeout(hideTimer);
  dockAnchor.dataset.visible = String(visible);
  dockAnchor.inert = !visible;
}

function hideAfterLeave() {
  clearTimeout(hideTimer);
  if (!autoHide.checked || !picker.hidden || draggedApp) return;
  hideTimer = setTimeout(() => {
    if (!dockAnchor.matches(":hover") && !screenEdge.matches(":hover")) setDockVisible(false);
  }, 360);
}

function closePicker() {
  picker.hidden = true;
  dockAnchor.dataset.picking = "false";
  pickerButton = null;
  hideAfterLeave();
}

function activateWindow(app, window, opened = false) {
  const restored = Boolean(window.minimized);
  window.minimized = false;
  active = { app, window };
  closePicker();
  renderWindow();
  updateStatus((opened ? "已打开 " : restored ? "已恢复 " : "已切回 ") + window.title);
}

function openPicker(app, button) {
  const sameButton = pickerButton === button;
  closePicker();
  if (sameButton) return;

  pickerButton = button;
  dockAnchor.dataset.picking = "true";
  byId("picker-title").textContent = app.name + " · 选择窗口";
  const items = app.windows.map((window) => {
    const item = document.createElement("button");
    item.className = "picker-item";
    item.type = "button";
    item.textContent = window.title;
    if (window.minimized) {
      const detail = document.createElement("span");
      detail.className = "picker-detail";
      detail.textContent = "最小化";
      item.append(detail);
    }
    item.addEventListener("click", () => activateWindow(app, window));
    return item;
  });
  byId("picker-items").replaceChildren(...items);
  const frame = desktop.getBoundingClientRect();
  const target = button.getBoundingClientRect();
  const anchor = dockAnchor.getBoundingClientRect();
  const center = Math.min(frame.right - 132, Math.max(frame.left + 132, target.left + target.width / 2));
  picker.style.setProperty("--picker-x", center - anchor.left + "px");
  picker.hidden = false;
  setDockVisible(true);
  resetHover();
  items[0]?.focus({ preventScroll: true });
  updateStatus("从列表选择一个要切回的窗口。");
}

function buttons() {
  return Array.from(dock.querySelectorAll(".dock-app"));
}

function resetHover() {
  for (const button of buttons()) {
    button.style.removeProperty("--zoom");
    button.style.removeProperty("--lift");
    button.style.removeProperty("--shift");
  }
}

function handleHover(event) {
  if (!magnify.checked || draggedApp || !picker.hidden) return;
  const target = event.target.closest(".dock-app");
  if (!target) {
    resetHover();
    return;
  }
  for (const button of buttons()) {
    const box = button.getBoundingClientRect();
    const distance = box.left + box.width / 2 - event.clientX;
    const wave = Math.max(0, 1 - Math.abs(distance) / (box.width * 1.55));
    const weight = button === target ? (variant.key === "A" ? Math.max(.7, wave) : 1) : (variant.key === "A" ? wave * .66 : 0);
    button.style.setProperty("--zoom", String(1 + (variant.scale - 1) * weight));
    button.style.setProperty("--lift", -12 * weight + "px");
    button.style.setProperty("--shift", (button === target ? 0 : Math.sign(distance) * 7 * weight) + "px");
  }
}

function selectVariant(offset) {
  const index = (variants.indexOf(variant) + offset + variants.length) % variants.length;
  closePicker();
  variant = variants[index];
  const url = new URL(location.href);
  url.searchParams.set("variant", variant.key);
  history.replaceState(null, "", url);
  renderDock();
  updateStatus("布局已切换为「" + variant.name + "」。");
}

function clearDropMarker() {
  dock.querySelector("[data-drop]")?.removeAttribute("data-drop");
}

function finishDrag() {
  draggedApp = null;
  dockAnchor.dataset.dragging = "false";
  dock.querySelector("[data-dragging]")?.removeAttribute("data-dragging");
  clearDropMarker();
  hideAfterLeave();
}

dock.addEventListener("pointermove", handleHover);
dock.addEventListener("pointerleave", resetHover);
dock.addEventListener("click", (event) => {
  const button = event.target.closest(".dock-app");
  if (!button || draggedApp) return;
  const app = pinned.find((item) => item.id === button.dataset.app);
  if (app.windows.length > 1) {
    openPicker(app, button);
  } else if (app.windows.length === 1) {
    activateWindow(app, app.windows[0]);
  } else {
    const newWindow = { title: app.name, lines: ["已从程序坞打开这个示例应用。"] };
    app.windows.push(newWindow);
    activateWindow(app, newWindow, true);
    renderDock();
  }
});

dock.addEventListener("dragstart", (event) => {
  const button = event.target.closest(".dock-app");
  if (!button) return;
  closePicker();
  draggedApp = pinned.find((app) => app.id === button.dataset.app);
  event.dataTransfer.setData("text/plain", draggedApp.id);
  event.dataTransfer.effectAllowed = "move";
  button.dataset.dragging = "true";
  dockAnchor.dataset.dragging = "true";
  resetHover();
});
dock.addEventListener("dragover", (event) => {
  if (!draggedApp) return;
  clearDropMarker();
  const target = event.target.closest(".dock-app");
  if (!target || target.dataset.app === draggedApp.id) return;
  event.preventDefault();
  event.dataTransfer.dropEffect = "move";
  const bounds = target.getBoundingClientRect();
  target.dataset.drop = event.clientX < bounds.left + bounds.width / 2 ? "before" : "after";
});
dock.addEventListener("dragleave", (event) => {
  if (!dock.contains(event.relatedTarget)) clearDropMarker();
});
dock.addEventListener("drop", (event) => {
  const target = event.target.closest(".dock-app");
  if (!draggedApp || !target?.dataset.drop) return;
  event.preventDefault();
  const moved = pinned.splice(pinned.indexOf(draggedApp), 1)[0];
  const targetIndex = pinned.findIndex((app) => app.id === target.dataset.app);
  pinned.splice(targetIndex + (target.dataset.drop === "after" ? 1 : 0), 0, moved);
  finishDrag();
  renderDock();
  updateStatus("已调整「" + moved.name + "」的位置。");
});
dock.addEventListener("dragend", finishDrag);

byId("minimize-window").addEventListener("click", () => {
  const title = active.window.title;
  active.window.minimized = true;
  active = null;
  renderWindow();
  updateStatus("已最小化 " + title + "。");
});
byId("close-window").addEventListener("click", () => {
  const title = active.window.title;
  active.app.windows.splice(active.app.windows.indexOf(active.window), 1);
  active = null;
  renderWindow();
  renderDock();
  updateStatus("已关闭 " + title + "。");
});
byId("previous-variant").addEventListener("click", () => selectVariant(-1));
byId("next-variant").addEventListener("click", () => selectVariant(1));

document.querySelectorAll('input[name="scene"]').forEach((input) => {
  input.addEventListener("change", () => {
    desktop.dataset.scene = input.value;
    updateStatus(input.value === "maximized" ? "示例窗口铺满桌面，程序坞浮在内容上方。" : "已返回普通桌面。");
  });
});
magnify.addEventListener("change", () => {
  resetHover();
  updateStatus(magnify.checked ? "悬停放大已开启。" : "悬停放大已关闭。");
});
autoHide.addEventListener("change", () => {
  closePicker();
  desktop.dataset.autoHide = String(autoHide.checked);
  setDockVisible(!autoHide.checked);
  updateStatus(autoHide.checked ? "移到预览桌面的底边中段即可唤出。" : "程序坞已设为常驻。");
});
screenEdge.addEventListener("pointerenter", () => {
  if (autoHide.checked) setDockVisible(true);
});
screenEdge.addEventListener("pointerleave", hideAfterLeave);
dockAnchor.addEventListener("pointerenter", () => clearTimeout(hideTimer));
dockAnchor.addEventListener("pointerleave", hideAfterLeave);
document.addEventListener("pointerdown", (event) => {
  if (!picker.hidden && !dockAnchor.contains(event.target)) closePicker();
});
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && !picker.hidden) {
    const trigger = pickerButton;
    closePicker();
    trigger?.focus({ preventScroll: true });
  }
  if (event.target.closest?.("input, textarea, select, [contenteditable]")) return;
  if (event.key === "ArrowLeft" || event.key === "ArrowRight") {
    event.preventDefault();
    selectVariant(event.key === "ArrowLeft" ? -1 : 1);
  }
});

renderDock();
renderWindow();
