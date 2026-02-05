document.addEventListener('DOMContentLoaded', () => {
    const timestampElement = document.getElementById('timestamp');
    const now = new Date();
    if (timestampElement) {
        timestampElement.textContent = now.toLocaleString();
    }

    const marketData = {
        crypto: {
            name: 'Crypto',
            summary: 'Always-on markets with fast regime shifts and deep on-chain data.',
            edges: [
                'Funding rate spreads and basis tracking across venues.',
                'Liquidation cluster alerts near key price levels.',
                'On-chain flow changes for exchanges and smart money wallets.',
                'Order book imbalance and volatility regime shifts.',
                'Event catalysts like listings, upgrades, and unlocks.'
            ]
        },
        forex: {
            name: 'Forex',
            summary: 'Macro-driven markets where session overlaps create volatility.',
            edges: [
                'Session overlap alerts for liquidity spikes.',
                'Macro calendar surprises versus consensus.',
                'Rate differential monitoring and carry shifts.',
                'Risk-on or risk-off correlation mapping.',
                'Liquidity sweeps around major weekly levels.'
            ]
        },
        collectibles: {
            name: 'Pokemon cards',
            summary: 'Illiquid markets where pricing comes from comps and scarcity.',
            edges: [
                'Population report deltas and low-pop alerts.',
                'Recent comps with grade and condition adjustments.',
                'Marketplace spread tracking across major platforms.',
                'Grading turnaround time and fee monitoring.',
                'Set-level demand trends and liquidity mapping.'
            ]
        },
        meme: {
            name: 'Meme coins',
            summary: 'Narrative-driven flows with rapid sentiment changes.',
            edges: [
                'Social velocity and unique mention tracking.',
                'Liquidity pool lock status and concentration risk.',
                'CEX and DEX listing detection and alerting.',
                'Cross-chain inflow spikes and bridge activity.',
                'Contract risk checks and developer activity monitoring.'
            ]
        }
    };

    const marketName = document.getElementById('marketName');
    const marketSummary = document.getElementById('marketSummary');
    const edgeList = document.getElementById('edgeList');
    const marketButtons = document.querySelectorAll('[data-market]');

    const renderMarket = (marketKey) => {
        const data = marketData[marketKey];
        if (!data || !edgeList) {
            return;
        }

        if (marketName) {
            marketName.textContent = data.name;
        }
        if (marketSummary) {
            marketSummary.textContent = data.summary;
        }

        edgeList.innerHTML = '';
        data.edges.forEach((edge) => {
            const item = document.createElement('li');
            item.textContent = edge;
            edgeList.appendChild(item);
        });

        marketButtons.forEach((button) => {
            button.classList.toggle('active', button.dataset.market === marketKey);
        });
    };

    marketButtons.forEach((button) => {
        button.addEventListener('click', () => {
            renderMarket(button.dataset.market);
        });
    });

    renderMarket('crypto');

    const copyButton = document.getElementById('copyPlan');
    const planText = [
        'Clawd Bot setup plan',
        '1. Define watchlists per market and time horizon.',
        '2. Connect price, news, and sentiment data feeds.',
        '3. Add alert thresholds and anomaly detection rules.',
        '4. Build daily and weekly review summaries.',
        '5. Start with paper trading and iterate on signals.',
        '6. Add risk guardrails before going live.'
    ].join('\n');

    const copyPlan = async () => {
        if (!copyButton) {
            return;
        }

        try {
            if (navigator.clipboard && navigator.clipboard.writeText) {
                await navigator.clipboard.writeText(planText);
            } else {
                const temp = document.createElement('textarea');
                temp.value = planText;
                document.body.appendChild(temp);
                temp.select();
                document.execCommand('copy');
                document.body.removeChild(temp);
            }
            copyButton.textContent = 'Copied';
            setTimeout(() => {
                copyButton.textContent = 'Copy setup plan';
            }, 2000);
        } catch (error) {
            console.warn('Copy failed', error);
            copyButton.textContent = 'Copy failed';
            setTimeout(() => {
                copyButton.textContent = 'Copy setup plan';
            }, 2000);
        }
    };

    if (copyButton) {
        copyButton.addEventListener('click', copyPlan);
    }

    const statusBadge = document.getElementById('statusBadge');
    const lastRun = document.getElementById('lastRun');
    const signalCount = document.getElementById('signalCount');
    const signalList = document.getElementById('signalList');
    const signalEmpty = document.getElementById('signalEmpty');
    const refreshStatusButton = document.getElementById('refreshStatus');

    const setStatusBadge = (online) => {
        if (!statusBadge) {
            return;
        }
        statusBadge.textContent = online ? 'Online' : 'Offline';
        statusBadge.classList.toggle('online', online);
        statusBadge.classList.toggle('offline', !online);
    };

    const renderSignals = (signals) => {
        if (!signalList) {
            return;
        }
        signalList.innerHTML = '';
        const hasSignals = Array.isArray(signals) && signals.length > 0;
        if (signalEmpty) {
            signalEmpty.style.display = hasSignals ? 'none' : 'block';
        }
        if (!hasSignals) {
            return;
        }
        signals.forEach((signal) => {
            const item = document.createElement('li');
            item.textContent = `[${signal.market}] ${signal.message}`;
            signalList.appendChild(item);
        });
    };

    const refreshStatus = async () => {
        if (!statusBadge || !lastRun || !signalCount) {
            return;
        }
        try {
            const response = await fetch('/api/status', { cache: 'no-store' });
            if (!response.ok) {
                throw new Error('Status unavailable');
            }
            const status = await response.json();
            setStatusBadge(true);
            lastRun.textContent = status.lastRun
                ? new Date(status.lastRun.at).toLocaleString()
                : 'Not run yet';
            signalCount.textContent =
                typeof status.signalCount === 'number'
                    ? status.signalCount
                    : '--';

            const signalsResponse = await fetch('/api/signals?limit=5', {
                cache: 'no-store'
            });
            if (!signalsResponse.ok) {
                throw new Error('Signals unavailable');
            }
            const signalPayload = await signalsResponse.json();
            renderSignals(signalPayload.signals || []);
        } catch (error) {
            setStatusBadge(false);
            lastRun.textContent = 'Bot API offline';
            signalCount.textContent = '--';
            renderSignals([]);
        }
    };

    if (refreshStatusButton) {
        refreshStatusButton.addEventListener('click', refreshStatus);
    }

    refreshStatus();
    setInterval(refreshStatus, 60000);
});
