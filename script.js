// Add current timestamp to the page
document.addEventListener('DOMContentLoaded', function() {
    const timestampElement = document.getElementById('timestamp');
    const now = new Date();
    timestampElement.textContent = now.toLocaleString();
    
    // Add a simple animation to the header
    const header = document.querySelector('header');
    setTimeout(() => {
        header.style.transition = 'all 0.5s ease';
        header.style.transform = 'scale(1.02)';
        setTimeout(() => {
            header.style.transform = 'scale(1)';
        }, 500);
    }, 1000);
    
    // Log successful load
    console.log('AI Agent Test Project loaded successfully at ' + now.toLocaleString());
});
