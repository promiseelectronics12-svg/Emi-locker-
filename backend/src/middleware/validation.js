// Alias for validateRequest — some modules require 'validation', others 'validateRequest'
const { validateRequest } = require('./validateRequest');
module.exports = { validateRequest, validate: validateRequest };
