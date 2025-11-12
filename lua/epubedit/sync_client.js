/**
 * EpubEdit Browser Sync Client
 * Connects to SSE endpoint and reloads page on file changes
 */
(function() {
    'use strict';

    const SSE_ENDPOINT = '/__epubedit_sync__';
    let eventSource = null;
    let reconnectAttempts = 0;
    const MAX_RECONNECT_ATTEMPTS = 10;
    const RECONNECT_DELAY = 1000;

    function log(message) {
        console.log('[EpubEdit Sync] ' + message);
    }

    function connect() {
        if (eventSource) {
            eventSource.close();
        }

        log('Connecting to sync server...');
        eventSource = new EventSource(SSE_ENDPOINT);

        eventSource.onopen = function() {
            log('Connected - auto-reload enabled');
            reconnectAttempts = 0;
        };

        eventSource.onmessage = function(e) {
            if (e.data === 'reload') {
                log('File changed - reloading page');
                window.location.reload();
            }
        };

        eventSource.onerror = function() {
            log('Connection error');
            eventSource.close();

            if (reconnectAttempts < MAX_RECONNECT_ATTEMPTS) {
                reconnectAttempts++;
                const delay = RECONNECT_DELAY * Math.pow(1.5, reconnectAttempts - 1);
                log('Reconnecting in ' + Math.round(delay / 1000) + 's (attempt ' + reconnectAttempts + ')');
                setTimeout(connect, delay);
            } else {
                log('Max reconnect attempts reached - sync disabled');
            }
        };
    }

    function cleanup() {
        if (eventSource) {
            eventSource.close();
            eventSource = null;
        }
    }

    window.addEventListener('beforeunload', cleanup);

    connect();
})();
