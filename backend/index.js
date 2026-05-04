const express = require('express');

const app = express();

const PORT = process.env.PORT || 3000;

app.listen(PORT, () => {
  console.log(`EMI Locker API running on port ${PORT}`);
});

module.exports = app;