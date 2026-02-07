module.exports = {
  apps: [
    {
      name: 'clawd-bot',
      script: 'server.js',
      cwd: __dirname,
      autorestart: true,
      max_restarts: 10,
      watch: false,
      env: {
        NODE_ENV: 'production'
      }
    }
  ]
};
