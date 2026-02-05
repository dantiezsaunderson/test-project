const axios = require('axios');
const config = require('./config');

const formatSummary = (signals) => {
    const byMarket = signals.reduce((acc, signal) => {
        acc[signal.market] = (acc[signal.market] || 0) + 1;
        return acc;
    }, {});

    const markets = Object.entries(byMarket)
        .map(([market, count]) => `${market}: ${count}`)
        .join(', ');

    return `Clawd bot alert: ${signals.length} signal(s) (${markets}).`;
};

const notify = async (signals) => {
    if (!signals.length) {
        return;
    }

    if (config.alerts.enableConsole) {
        console.log(formatSummary(signals));
        signals.forEach((signal) => {
            console.log(`[${signal.market}] ${signal.message}`);
        });
    }

    if (config.alerts.webhookUrl) {
        try {
            await axios.post(config.alerts.webhookUrl, {
                text: formatSummary(signals),
                signals
            });
        } catch (error) {
            console.warn('Webhook delivery failed:', error.message);
        }
    }
};

module.exports = {
    notify
};
