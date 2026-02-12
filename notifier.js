const axios = require('axios');
const nodemailer = require('nodemailer');
const config = require('./config');

let emailTransporter = null;

const getEmailTransporter = () => {
    const settings = config.alerts.email;
    if (!settings.enabled) {
        return null;
    }
    if (emailTransporter) {
        return emailTransporter;
    }
    if (!settings.smtpHost || !settings.smtpPort) {
        console.warn('Email alerts enabled but SMTP host/port missing.');
        return null;
    }
    if (!settings.from || !settings.to.length) {
        console.warn('Email alerts enabled but from/to missing.');
        return null;
    }
    emailTransporter = nodemailer.createTransport({
        host: settings.smtpHost,
        port: settings.smtpPort,
        secure: settings.smtpSecure,
        auth: settings.smtpUser
            ? {
                  user: settings.smtpUser,
                  pass: settings.smtpPass
              }
            : undefined
    });
    return emailTransporter;
};

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

const formatSignalLines = (signals) =>
    signals.map((signal) => `[${signal.market}] ${signal.message}`).join('\n');

const formatAutoTradeSummary = (actions) =>
    `Clawd bot auto-trade: ${actions.length} order(s).`;

const formatAutoTradeLines = (actions) =>
    actions
        .map((action) => {
            const side = String(action.side || '').toUpperCase();
            const status = action.status || 'submitted';
            return `${action.instId} ${side} size ${action.size} @ ${action.price} (${status})`;
        })
        .join('\n');

const sendEmail = async ({ subject, text }) => {
    const settings = config.alerts.email;
    if (!settings.enabled) {
        return;
    }
    const transporter = getEmailTransporter();
    if (!transporter) {
        return;
    }
    try {
        await transporter.sendMail({
            from: settings.from,
            to: settings.to.join(', '),
            subject,
            text
        });
    } catch (error) {
        console.warn('Email delivery failed:', error.message);
    }
};

const notify = async (signals) => {
    if (!signals.length) {
        return;
    }

    const summary = formatSummary(signals);
    if (config.alerts.enableConsole) {
        console.log(summary);
        signals.forEach((signal) => {
            console.log(`[${signal.market}] ${signal.message}`);
        });
    }

    if (config.alerts.webhookUrl) {
        try {
            await axios.post(config.alerts.webhookUrl, {
                text: summary,
                signals
            });
        } catch (error) {
            console.warn('Webhook delivery failed:', error.message);
        }
    }

    await sendEmail({
        subject: `Clawd bot signals (${signals.length})`,
        text: `${summary}\n\n${formatSignalLines(signals)}`
    });
};

const notifyAutoTrades = async (actions) => {
    if (!actions.length) {
        return;
    }
    const settings = config.alerts.email;
    const filtered = settings.includeDryRun
        ? actions
        : actions.filter((action) => action.status !== 'dry-run');
    if (!filtered.length) {
        return;
    }

    const summary = formatAutoTradeSummary(filtered);
    if (config.alerts.enableConsole) {
        console.log(summary);
        filtered.forEach((action) => {
            const side = String(action.side || '').toUpperCase();
            console.log(
                `${action.instId} ${side} size ${action.size} @ ${action.price} (${action.status})`
            );
        });
    }

    await sendEmail({
        subject: `Clawd bot auto-trade (${filtered.length})`,
        text: `${summary}\n\n${formatAutoTradeLines(filtered)}`
    });
};

module.exports = {
    notify,
    notifyAutoTrades
};
