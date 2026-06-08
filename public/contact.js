const form = document.querySelector('#contact-form');
const statusText = document.querySelector('#form-status');

const endpoint =
  'https://your-region-your-firebase-project-id.cloudfunctions.net/submitContactForm';

form?.addEventListener('submit', async (event) => {
  event.preventDefault();
  const submitButton = form.querySelector('button[type="submit"]');
  const formData = new FormData(form);
  const payload = Object.fromEntries(formData.entries());

  statusText.textContent = '';
  submitButton.disabled = true;
  submitButton.textContent = '送信中';

  try {
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      throw new Error('送信に失敗しました');
    }

    form.reset();
    statusText.textContent = '送信しました。内容を確認して、必要に応じて返信します。';
    statusText.className = 'form-status success';
  } catch (_) {
    statusText.textContent =
      '送信できませんでした。時間を置いてもう一度お試しください。';
    statusText.className = 'form-status error';
  } finally {
    submitButton.disabled = false;
    submitButton.textContent = '送信する';
  }
});
