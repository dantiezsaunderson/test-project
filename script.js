document.addEventListener('DOMContentLoaded', () => {
    const now = new Date();
    const formattedDate = now.toLocaleDateString('en-US', {
        year: 'numeric',
        month: 'short',
        day: 'numeric'
    });

    const timestampElement = document.getElementById('timestamp');
    if (timestampElement) {
        timestampElement.textContent = formattedDate;
    }

    const lastUpdated = document.getElementById('last-updated');
    if (lastUpdated) {
        lastUpdated.textContent = formattedDate;
    }

    const shareMessage = document.getElementById('share-message');
    const copyMessageButton = document.getElementById('copy-message');
    const resetMessageButton = document.getElementById('reset-message');
    const copyShareButton = document.getElementById('copy-share');
    const copyLinkButton = document.getElementById('copy-link');

    const defaultMessage = shareMessage ? shareMessage.value.trim() : '';

    const copyText = (text, button) => {
        if (!text) {
            return;
        }

        const handleCopied = () => {
            if (!button) {
                return;
            }
            const original = button.textContent;
            button.textContent = 'Copied';
            setTimeout(() => {
                button.textContent = original;
            }, 1400);
        };

        if (navigator.clipboard && window.isSecureContext) {
            navigator.clipboard.writeText(text).then(handleCopied).catch(() => {
                handleCopied();
            });
            return;
        }

        const fallback = document.createElement('textarea');
        fallback.value = text;
        fallback.setAttribute('readonly', '');
        fallback.style.position = 'absolute';
        fallback.style.left = '-9999px';
        document.body.appendChild(fallback);
        fallback.select();
        document.execCommand('copy');
        document.body.removeChild(fallback);
        handleCopied();
    };

    if (copyMessageButton && shareMessage) {
        copyMessageButton.addEventListener('click', () => {
            copyText(shareMessage.value.trim(), copyMessageButton);
        });
    }

    if (copyShareButton && shareMessage) {
        copyShareButton.addEventListener('click', () => {
            copyText(shareMessage.value.trim(), copyShareButton);
        });
    }

    if (copyLinkButton) {
        copyLinkButton.addEventListener('click', () => {
            const link = copyLinkButton.getAttribute('data-copy-link') || '';
            copyText(link, copyLinkButton);
        });
    }

    document.querySelectorAll('[data-copy]').forEach((button) => {
        button.addEventListener('click', () => {
            const text = button.getAttribute('data-copy') || '';
            copyText(text, button);
        });
    });

    if (resetMessageButton && shareMessage) {
        resetMessageButton.addEventListener('click', () => {
            shareMessage.value = defaultMessage;
        });
    }

    const checklistItems = Array.from(
        document.querySelectorAll('input[type="checkbox"][data-check]')
    );
    const progressBar = document.getElementById('progress-bar');
    const progressText = document.getElementById('progress-text');
    const resetChecklistButton = document.getElementById('reset-checklist');
    const storageKey = 'signalChecklist';

    const updateProgress = () => {
        if (!progressBar || !progressText) {
            return;
        }
        const total = checklistItems.length;
        const completed = checklistItems.filter((item) => item.checked).length;
        const percent = total ? Math.round((completed / total) * 100) : 0;
        progressBar.style.width = percent + '%';
        progressText.textContent = `${completed} / ${total} complete`;
    };

    const saveChecklist = () => {
        const data = {};
        checklistItems.forEach((item) => {
            data[item.dataset.check] = item.checked;
        });
        localStorage.setItem(storageKey, JSON.stringify(data));
    };

    const loadChecklist = () => {
        const saved = localStorage.getItem(storageKey);
        if (!saved) {
            updateProgress();
            return;
        }
        try {
            const data = JSON.parse(saved);
            checklistItems.forEach((item) => {
                item.checked = Boolean(data[item.dataset.check]);
            });
        } catch (error) {
            localStorage.removeItem(storageKey);
        }
        updateProgress();
    };

    checklistItems.forEach((item) => {
        item.addEventListener('change', () => {
            saveChecklist();
            updateProgress();
        });
    });

    if (resetChecklistButton) {
        resetChecklistButton.addEventListener('click', () => {
            checklistItems.forEach((item) => {
                item.checked = false;
            });
            saveChecklist();
            updateProgress();
        });
    }

    loadChecklist();
});
