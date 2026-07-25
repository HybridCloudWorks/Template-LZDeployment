/* Minimal DOM stub so app.js can be loaded in Node and its pure logic exercised.
 * We stop app.js short of init() by never firing DOMContentLoaded. */
const fs = require('fs');
const path = require('path');

// Resolved relative to this file so the suite runs from any checkout.
const SITE = path.resolve(__dirname, '..', '..', 'site');

function el() {
  const e = {
    style: {}, dataset: {}, classList: { toggle(){}, add(){}, remove(){}, contains(){return false;} },
    children: [], value: '', checked: false, hidden: false, disabled: false,
    textContent: '', innerHTML: '', appendChild(c){ this.children.push(c); return c; },
    removeChild(){}, addEventListener(){}, setAttribute(){}, focus(){}, click(){},
    querySelector(){ return el(); }, querySelectorAll(){ return []; }
  };
  return e;
}

global.document = {
  querySelector: () => el(),
  querySelectorAll: () => [],
  createElement: () => el(),
  createRange: () => ({ selectNodeContents(){} }),
  addEventListener: () => {},
  body: el()
};
global.window = { getSelection: () => ({ removeAllRanges(){}, addRange(){} }), addEventListener(){} };
global.navigator = {};
global.localStorage = { getItem: () => null, setItem: () => {}, };
global.requestAnimationFrame = (fn) => setTimeout(fn, 0);
global.Blob = class { constructor(p){ this.parts = p; } };
global.URL = { createObjectURL: () => 'blob:x', revokeObjectURL: () => {} };
global.FileReader = class {};
global.setInterval = () => 0;

const src = fs.readFileSync(path.join(SITE, 'app.js'), 'utf8');
// Expose internals for testing.
const wrapped = src + '\n;module.exports = { validate, estimateRum, buildConfig, tfvarsGlobal, tfvarsConnectivity, backendHcl, environmentDefinitions, deploymentMetadata, configurationMarkdown, nextStepsMarkdown, defaultConfig, cidrsOverlap, get config(){return config;}, set config(v){config=v;}, get defaultTagRows(){return defaultTagRows;}, set defaultTagRows(v){defaultTagRows=v;} };';
const mod = { exports: {} };
new Function('module', 'exports', 'require', wrapped)(mod, mod.exports, require);
module.exports = mod.exports;
