// SysMonitorModel.js - Core parsing & statistics engine for omarchy sys-monitor

.pragma library

function defaultSettings() {
  return {
    showCpu: true,
    showRam: true,
    showStorage: true,
    showExternalStorage: true,
    showNet: true,
    showNetUpload: false,
    showIcons: true,
    refreshInterval: 2000
  };
}

function parseCpuStat(statText, prevState) {
  if (!statText || typeof statText !== "string") {
    return prevState || { usage: 0, cores: [], total: 0, idle: 0, rawCores: [] };
  }

  var lines = statText.trim().split("\n");
  var overallLine = null;
  var coreLines = [];

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim();
    if (line.indexOf("cpu ") === 0) {
      overallLine = line;
    } else if (line.indexOf("cpu") === 0) {
      coreLines.push(line);
    }
  }

  if (!overallLine) {
    return prevState || { usage: 0, cores: [], total: 0, idle: 0, rawCores: [] };
  }

  // Parse overall CPU
  var parts = overallLine.split(/\s+/).slice(1);
  var user = parseFloat(parts[0]) || 0;
  var nice = parseFloat(parts[1]) || 0;
  var system = parseFloat(parts[2]) || 0;
  var idle = parseFloat(parts[3]) || 0;
  var iowait = parseFloat(parts[4]) || 0;
  var irq = parseFloat(parts[5]) || 0;
  var softirq = parseFloat(parts[6]) || 0;
  var steal = parseFloat(parts[7]) || 0;

  var totalTime = user + nice + system + idle + iowait + irq + softirq + steal;
  var idleTime = idle + iowait;

  var overallUsage = 0;
  if (prevState && prevState.total && prevState.total > 0) {
    var deltaTotal = totalTime - prevState.total;
    var deltaIdle = idleTime - prevState.idle;
    if (deltaTotal > 0) {
      overallUsage = Math.max(0, Math.min(100, Math.round((1 - deltaIdle / deltaTotal) * 100)));
    } else {
      overallUsage = prevState.usage || 0;
    }
  }

  // Parse per-core CPU
  var cores = [];
  var rawCores = [];
  for (var c = 0; c < coreLines.length; c++) {
    var cparts = coreLines[c].split(/\s+/).slice(1);
    var cUser = parseFloat(cparts[0]) || 0;
    var cNice = parseFloat(cparts[1]) || 0;
    var cSys = parseFloat(cparts[2]) || 0;
    var cIdle = parseFloat(cparts[3]) || 0;
    var cIowait = parseFloat(cparts[4]) || 0;
    var cIrq = parseFloat(cparts[5]) || 0;
    var cSoftirq = parseFloat(cparts[6]) || 0;
    var cSteal = parseFloat(cparts[7]) || 0;

    var cTotal = cUser + cNice + cSys + cIdle + cIowait + cIrq + cSoftirq + cSteal;
    var cIdleTime = cIdle + cIowait;
    rawCores.push({ total: cTotal, idle: cIdleTime });

    var coreUsage = 0;
    if (prevState && prevState.rawCores && prevState.rawCores[c]) {
      var prevCore = prevState.rawCores[c];
      var cdTotal = cTotal - prevCore.total;
      var cdIdle = cIdleTime - prevCore.idle;
      if (cdTotal > 0) {
        coreUsage = Math.max(0, Math.min(100, Math.round((1 - cdIdle / cdTotal) * 100)));
      } else if (prevState.cores && prevState.cores[c] !== undefined) {
        coreUsage = prevState.cores[c];
      }
    }
    cores.push(coreUsage);
  }

  return {
    usage: overallUsage,
    cores: cores,
    total: totalTime,
    idle: idleTime,
    rawCores: rawCores
  };
}

function parseMemInfo(meminfoText) {
  if (!meminfoText || typeof meminfoText !== "string") {
    return {
      percent: 0,
      usedGB: "0.0",
      totalGB: "0.0",
      freeGB: "0.0",
      availableGB: "0.0",
      swapPercent: 0,
      swapUsedGB: "0.0",
      swapTotalGB: "0.0"
    };
  }

  var lines = meminfoText.trim().split("\n");
  var mem = {};
  for (var i = 0; i < lines.length; i++) {
    var colonIdx = lines[i].indexOf(":");
    if (colonIdx > 0) {
      var key = lines[i].substring(0, colonIdx).trim();
      var val = parseInt(lines[i].substring(colonIdx + 1).trim(), 10);
      if (!isNaN(val)) {
        mem[key] = val; // in kB
      }
    }
  }

  var totalKB = mem.MemTotal || 0;
  var availKB = mem.MemAvailable !== undefined ? mem.MemAvailable : (mem.MemFree || 0);
  var usedKB = Math.max(0, totalKB - availKB);

  var percent = totalKB > 0 ? Math.round((usedKB / totalKB) * 100) : 0;
  var usedGB = (usedKB / 1048576).toFixed(1);
  var totalGB = (totalKB / 1048576).toFixed(1);
  var freeGB = ((mem.MemFree || 0) / 1048576).toFixed(1);
  var availableGB = (availKB / 1048576).toFixed(1);

  var swapTotalKB = mem.SwapTotal || 0;
  var swapFreeKB = mem.SwapFree || 0;
  var swapUsedKB = Math.max(0, swapTotalKB - swapFreeKB);
  var swapPercent = swapTotalKB > 0 ? Math.round((swapUsedKB / swapTotalKB) * 100) : 0;
  var swapUsedGB = (swapUsedKB / 1048576).toFixed(1);
  var swapTotalGB = (swapTotalKB / 1048576).toFixed(1);

  return {
    percent: percent,
    usedGB: usedGB,
    totalGB: totalGB,
    freeGB: freeGB,
    availableGB: availableGB,
    swapPercent: swapPercent,
    swapUsedGB: swapUsedGB,
    swapTotalGB: swapTotalGB
  };
}

function formatSpeed(bytesPerSec) {
  var b = Math.max(0, Number(bytesPerSec) || 0);
  if (b < 1024) {
    return Math.round(b) + " B/s";
  } else if (b < 1024 * 1024) {
    var kb = b / 1024;
    return (kb < 10 ? kb.toFixed(1) : Math.round(kb)) + " KB/s";
  } else if (b < 1024 * 1024 * 1024) {
    var mb = b / (1024 * 1024);
    return (mb < 10 ? mb.toFixed(1) : Math.round(mb)) + " MB/s";
  } else {
    var gb = b / (1024 * 1024 * 1024);
    return gb.toFixed(2) + " GB/s";
  }
}

function parseNetDev(netDevText, prevState, deltaSeconds) {
  if (!netDevText || typeof netDevText !== "string") {
    return prevState || {
      rxSpeed: 0,
      txSpeed: 0,
      rxFormatted: "0 B/s",
      txFormatted: "0 B/s",
      totalRx: 0,
      totalTx: 0,
      activeIface: ""
    };
  }

  var lines = netDevText.trim().split("\n");
  var totalRx = 0;
  var totalTx = 0;
  var activeIface = "";
  var maxRx = -1;

  for (var i = 2; i < lines.length; i++) {
    var line = lines[i].trim();
    if (!line) continue;
    var parts = line.split(/\s+/);
    var iface = parts[0].replace(":", "");

    // Ignore loopback, docker, containers, virtual bridges
    if (iface === "lo" ||
        iface.indexOf("docker") === 0 ||
        iface.indexOf("veth") === 0 ||
        iface.indexOf("br-") === 0 ||
        iface.indexOf("virbr") === 0) {
      continue;
    }

    var rx = parseInt(parts[1], 10) || 0;
    var tx = parseInt(parts[9], 10) || 0;

    totalRx += rx;
    totalTx += tx;

    if (rx > maxRx) {
      maxRx = rx;
      activeIface = iface;
    }
  }

  var rxSpeed = 0;
  var txSpeed = 0;
  var dt = Math.max(0.1, Number(deltaSeconds) || 1.0);

  if (prevState && prevState.totalRx !== undefined && prevState.totalRx > 0) {
    var deltaRx = totalRx - prevState.totalRx;
    var deltaTx = totalTx - prevState.totalTx;
    if (deltaRx >= 0) rxSpeed = deltaRx / dt;
    if (deltaTx >= 0) txSpeed = deltaTx / dt;
  }

  return {
    rxSpeed: rxSpeed,
    txSpeed: txSpeed,
    rxFormatted: formatSpeed(rxSpeed),
    txFormatted: formatSpeed(txSpeed),
    totalRx: totalRx,
    totalTx: totalTx,
    activeIface: activeIface || "net"
  };
}

function parseLoadAvg(loadavgText) {
  if (!loadavgText || typeof loadavgText !== "string") return ["0.00", "0.00", "0.00"];
  var parts = loadavgText.trim().split(/\s+/);
  return [parts[0] || "0.00", parts[1] || "0.00", parts[2] || "0.00"];
}

function parseUptime(uptimeText) {
  if (!uptimeText || typeof uptimeText !== "string") return "0m";
  var parts = uptimeText.trim().split(/\s+/);
  var sec = parseFloat(parts[0]) || 0;
  var days = Math.floor(sec / 86400);
  var hours = Math.floor((sec % 86400) / 3600);
  var mins = Math.floor((sec % 3600) / 60);

  if (days > 0) {
    return days + "d " + hours + "h " + mins + "m";
  } else if (hours > 0) {
    return hours + "h " + mins + "m";
  } else {
    return mins + "m";
  }
}

function parseCpuModel(cpuinfoText) {
  if (!cpuinfoText || typeof cpuinfoText !== "string") return "CPU";
  var lines = cpuinfoText.split("\n");
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].indexOf("model name") === 0) {
      var parts = lines[i].split(":");
      if (parts.length > 1) {
        var name = parts[1].trim();
        // Clean up common verbose strings
        name = name.replace(/\(R\)/g, "")
                   .replace(/\(TM\)/g, "")
                   .replace(/CPU\s+/g, "")
                   .replace(/\s+/g, " ");
        return name;
      }
    }
  }
  return "Processor";
}

function formatBytes(bytes) {
  var b = Math.max(0, Number(bytes) || 0);
  if (b === 0) return "0 GB";
  var k = 1024;
  var sizes = ["B", "KB", "MB", "GB", "TB", "PB"];
  var i = Math.floor(Math.log(b) / Math.log(k));
  if (i < 0) i = 0;
  if (i >= sizes.length) i = sizes.length - 1;
  var val = b / Math.pow(k, i);
  return (val < 10 && i > 1 ? val.toFixed(1) : (i > 1 ? val.toFixed(1) : Math.round(val))) + " " + sizes[i];
}

function defaultStorageData() {
  return {
    internal: {
      name: "Root",
      model: "Internal Storage",
      mountpoint: "/",
      fstype: "",
      totalBytes: 0,
      usedBytes: 0,
      availBytes: 0,
      totalFormatted: "0 GB",
      usedFormatted: "0 GB",
      availFormatted: "0 GB",
      percent: 0,
      partitions: []
    },
    external: [],
    hasExternal: false,
    externalCount: 0,
    percent: 0
  };
}

function parseStorage(lsblkText) {
  var rootRes = defaultStorageData();
  if (!lsblkText || typeof lsblkText !== "string") return rootRes;

  var parsed;
  try {
    parsed = JSON.parse(lsblkText);
  } catch (e) {
    return rootRes;
  }

  var blockdevices = parsed.blockdevices || [];
  var internalRootNode = null;
  var internalRootDisk = null;
  var allInternalParts = [];
  var externalItems = [];

  function getMounts(node) {
    var mounts = [];
    if (Array.isArray(node.mountpoints)) {
      for (var i = 0; i < node.mountpoints.length; i++) {
        if (node.mountpoints[i] && node.mountpoints[i] !== "[SWAP]") {
          mounts.push(node.mountpoints[i]);
        }
      }
    }
    if (node.mountpoint && node.mountpoint !== "[SWAP]" && mounts.indexOf(node.mountpoint) === -1) {
      mounts.push(node.mountpoint);
    }
    return mounts;
  }

  // First pass: locate the device containing root "/"
  function findRoot(node, parentDisk) {
    var mounts = getMounts(node);
    if (mounts.indexOf("/") !== -1) {
      internalRootNode = node;
      internalRootDisk = parentDisk || node;
    }
    if (node.children && node.children.length > 0) {
      for (var c = 0; c < node.children.length; c++) {
        findRoot(node.children[c], parentDisk || node);
      }
    }
  }

  for (var i = 0; i < blockdevices.length; i++) {
    var dev = blockdevices[i];
    if (dev.name && (dev.name.indexOf("loop") === 0 || dev.name.indexOf("zram") === 0)) continue;
    if (dev.fstype === "swap") continue;
    findRoot(dev, dev);
  }

  // Second pass: collect internal partitions and external storage devices
  for (var i = 0; i < blockdevices.length; i++) {
    var dev = blockdevices[i];
    if (dev.name && (dev.name.indexOf("loop") === 0 || dev.name.indexOf("zram") === 0)) continue;
    if (dev.fstype === "swap") continue;

    var isDevInternalRoot = (internalRootDisk && dev.name === internalRootDisk.name);
    var isDevExternal = !isDevInternalRoot && (dev.tran === "usb" || dev.rm === true || dev.rm === 1 || dev.hotplug === true);

    function collectParts(node, parentDev, isExt) {
      var mounts = getMounts(node);
      var hasChildren = node.children && node.children.length > 0;

      for (var m = 0; m < mounts.length; m++) {
        if (mounts[m].indexOf("/run/media/") === 0 || mounts[m].indexOf("/media/") === 0) {
          isExt = true;
        }
      }

      if (!hasChildren) {
        if (node.fstype === "swap") return;
        var size = Number(node.size) || 0;
        var used = Number(node.fsused);
        var avail = Number(node.fsavail);
        var pct = 0;
        var mounted = mounts.length > 0;

        if (node["fsuse%"]) {
          pct = parseInt(node["fsuse%"], 10) || 0;
        } else if (!isNaN(used) && !isNaN(avail) && (used + avail) > 0) {
          pct = Math.round((used / (used + avail)) * 100);
        }

        var partObj = {
          name: node.name || "",
          path: node.path || ("/dev/" + node.name),
          label: node.label || "",
          model: parentDev.model || node.model || "",
          fstype: node.fstype || "",
          size: size,
          used: isNaN(used) ? 0 : used,
          avail: isNaN(avail) ? 0 : avail,
          sizeFormatted: formatBytes(size),
          usedFormatted: mounted && !isNaN(used) ? formatBytes(used) : "-",
          availFormatted: mounted && !isNaN(avail) ? formatBytes(avail) : "-",
          percent: pct,
          mountpoint: mounts[0] || "",
          mountpoints: mounts,
          isMounted: mounted
        };

        if (isExt) {
          var nameLabel = partObj.label || partObj.model || partObj.name;
          if (partObj.label && partObj.model && partObj.label !== partObj.model) {
            partObj.displayName = partObj.label + " (" + partObj.model + ")";
          } else {
            partObj.displayName = nameLabel;
          }
          externalItems.push(partObj);
        } else {
          allInternalParts.push(partObj);
        }
      } else {
        for (var c = 0; c < node.children.length; c++) {
          collectParts(node.children[c], parentDev, isExt);
        }
      }
    }

    collectParts(dev, dev, isDevExternal);
  }

  // Format internal root info
  if (internalRootNode) {
    var rUsed = Number(internalRootNode.fsused);
    var rAvail = Number(internalRootNode.fsavail);
    var rSize = Number(internalRootNode.size) || 0;
    var rPct = 0;
    if (internalRootNode["fsuse%"]) {
      rPct = parseInt(internalRootNode["fsuse%"], 10) || 0;
    } else if (!isNaN(rUsed) && !isNaN(rAvail) && (rUsed + rAvail) > 0) {
      rPct = Math.round((rUsed / (rUsed + rAvail)) * 100);
    }

    rootRes.internal = {
      name: internalRootNode.name || "root",
      model: (internalRootDisk && internalRootDisk.model) || "System Disk",
      mountpoint: "/",
      fstype: internalRootNode.fstype || "",
      totalBytes: rSize,
      usedBytes: isNaN(rUsed) ? 0 : rUsed,
      availBytes: isNaN(rAvail) ? 0 : rAvail,
      totalFormatted: formatBytes(rSize),
      usedFormatted: isNaN(rUsed) ? "0 GB" : formatBytes(rUsed),
      availFormatted: isNaN(rAvail) ? "0 GB" : formatBytes(rAvail),
      percent: rPct,
      partitions: allInternalParts.filter(function(p) {
        return p.mountpoint && p.mountpoint !== "/" && p.mountpoints.indexOf("/") === -1;
      })
    };
    rootRes.percent = rPct;
  } else if (allInternalParts.length > 0) {
    // Fallback if no explicit "/" was found
    var first = allInternalParts[0];
    rootRes.internal = {
      name: first.name,
      model: first.model || "Internal Disk",
      mountpoint: first.mountpoint || "/",
      fstype: first.fstype,
      totalBytes: first.size,
      usedBytes: first.used,
      availBytes: first.avail,
      totalFormatted: first.sizeFormatted,
      usedFormatted: first.usedFormatted,
      availFormatted: first.availFormatted,
      percent: first.percent,
      partitions: allInternalParts.slice(1)
    };
    rootRes.percent = first.percent;
  }

  rootRes.external = externalItems;
  rootRes.hasExternal = externalItems.length > 0;
  rootRes.externalCount = externalItems.length;

  return rootRes;
}
