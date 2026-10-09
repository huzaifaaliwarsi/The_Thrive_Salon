const imported = require('./dist/index.js');
const app = imported.app || imported.default || imported;
module.exports = app;
