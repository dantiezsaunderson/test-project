document.addEventListener('DOMContentLoaded', () => {
    const timestampElement = document.getElementById('timestamp');
    if (!timestampElement) {
        return;
    }

    const now = new Date();
    timestampElement.textContent = now.toLocaleString();
});
