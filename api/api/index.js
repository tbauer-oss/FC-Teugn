const app = require('../dist/server').default;

module.exports = (req, res) => {
  return app(req, res);
};
