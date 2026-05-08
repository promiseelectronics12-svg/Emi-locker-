import { useEffect, useState } from 'react';

export default function AmapiCallback() {
  const [token, setToken] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    setToken(params.get('enterpriseToken'));
  }, []);

  function copyToken() {
    if (!token) return;
    navigator.clipboard.writeText(token).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    });
  }

  return (
    <div style={{ fontFamily: 'sans-serif', display: 'flex', alignItems: 'center', justifyContent: 'center', minHeight: '100vh', margin: 0, background: '#f0fdf4' }}>
      <div style={{ background: 'white', borderRadius: 12, padding: 40, maxWidth: 520, width: '90%', boxShadow: '0 4px 24px rgba(0,0,0,0.08)', textAlign: 'center' }}>
        {token ? (
          <>
            <h1 style={{ color: '#065f46', fontSize: '1.4rem', marginBottom: 8 }}>✅ Enterprise Signup Complete</h1>
            <p style={{ color: '#6b7280', fontSize: '0.95rem', marginBottom: 24 }}>Copy the token below and paste it into your terminal.</p>
            <div style={{ fontSize: '0.75rem', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.05em', color: '#059669', marginBottom: 8 }}>Enterprise Token</div>
            <div style={{ background: '#ecfdf5', border: '2px solid #6ee7b7', borderRadius: 8, padding: 16, wordBreak: 'break-all', fontFamily: 'monospace', fontSize: '0.85rem', color: '#065f46', marginBottom: 20 }}>
              {token}
            </div>
            <button onClick={copyToken} style={{ background: '#059669', color: 'white', border: 'none', borderRadius: 8, padding: '10px 24px', fontSize: '0.95rem', cursor: 'pointer' }}>
              {copied ? '✓ Copied!' : 'Copy Token'}
            </button>
          </>
        ) : (
          <>
            <h1 style={{ color: '#dc2626', fontSize: '1.4rem' }}>⚠️ No Token Found</h1>
            <p style={{ color: '#6b7280', fontSize: '0.95rem' }}>Page opened without an enterprise token. Complete the Android Management signup wizard first.</p>
          </>
        )}
      </div>
    </div>
  );
}
