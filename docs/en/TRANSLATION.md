[中文文档](../README.md) | [English Docs](README.md) | [中文版本](../TRANSLATION.md)

# Pesty Translation Guide

Pesty can translate selected text directly from any app or translate text from
clipboard history, without requiring you to paste it elsewhere first. The
default global translation shortcut is `⇧⌘T`.

## Quick Start

### Translate Selected Text from Another App

1. Select a passage in a browser, document editor, or another app.
2. Press `⇧⌘T`.
3. Pesty displays a translation board near the selection and starts translating automatically.
4. Review the result and click “Copy Translation” to place it on the system clipboard.

Reading a text selection from another app requires macOS Accessibility
permission. On first use, follow the prompt and allow Pesty under
“System Settings → Privacy & Security → Accessibility.” Pesty never reads text
selected in secure fields or password fields.

### Translate Clipboard History

1. Press `⌘⇧V` to open Pesty and select a text-bearing or image card.
2. Press `⇧⌘T`, or right-click the card and choose “Translate.”
3. The translation board appears above the selected card and starts translating automatically.

Text, rich-text, and link cards enter translation directly. Image cards first
use macOS Vision to recognize text locally, then use the same translation
pipeline; you can retry if no readable text is detected. Ordinary files cannot
currently be translated directly.

The default `⇧⌘T` shortcut works both globally and inside the Pesty panel. You
can change it under “Settings → Translate & Explain → Translation shortcut.”

## Supported Languages

Pesty currently provides the following language options:

- English
- Chinese (Simplified)
- Japanese
- Korean
- French
- German
- Spanish

The source language can also be set to “Automatic.” Whether a specific language
pair is available ultimately depends on the selected translation service.

## Choose a Translation Service

Set the default service under
“Settings → Translate & Explain → Translation preferences,” or switch services
temporarily from the “More” menu in the upper-right corner of the translation
board.

| Service | Requirements | Behavior |
| --- | --- | --- |
| Automatic | Recommended | Prefers Apple Translation on macOS 15 and later. If Apple Translation is unavailable, a language pack is missing, or the language pair is unsupported, Pesty falls back to Doubao when it is configured. On macOS 14, Pesty uses configured Doubao or reports that no service is available. |
| Apple Translate | macOS 15 or later | Uses the Apple Translation framework provided by macOS. Doubao is not required, but the relevant language packs must be downloaded first. |
| Doubao (Volcengine Ark) | Any supported macOS version | Requires your own Volcengine Ark API key and model ID. The selected text is sent to Volcengine Ark for translation. |

OpenAI-compatible providers do not currently handle translation requests. They
appear on the same Settings page but currently power explanation only. Use
Apple Translation or Doubao for translation.

## Configure Apple Translation

Apple Translation does not require an API key in Pesty:

1. Confirm that the Mac is running macOS 15 or later.
2. Open “Settings → Translate & Explain.”
3. Set “Translation service” to “Apple Translate.”
4. Choose the default source and target languages.
5. Under “Apple Translate language packs,” inspect “Required baseline” and “Current language selection.”
6. Click “Download” for each pack marked “Not downloaded,” and keep Settings open until it reports “Downloaded and ready.”
7. Select text in any app, or select a text or image card in Pesty, then press `⇧⌘T`.

If the selected language pair is unavailable, choose different source or target
languages or configure Doubao. In Automatic mode, Pesty attempts to fall back
to configured Doubao when Apple Translation fails.

Pesty always checks the English and Simplified Chinese baseline pack together
with the currently selected language pair. When the source is Automatic, the
language detected at translation time may need an additional pack. To download
it in advance, choose an explicit source language first. After downloading the
packs, you can switch the service back to Automatic.

## Configure Doubao (Volcengine Ark)

Before starting, obtain a Volcengine Ark API key and the ID of a model your
account can invoke.

1. Open “Settings → Translate & Explain.”
2. In the “Doubao (Volcengine Ark)” section, click “Get an API key” to open the Volcengine Ark console.
3. Enter the API key in Pesty and click the adjacent “Save” button.
4. Enter the Ark model ID and click “Save.” The interface shows `doubao-seed-evolving` as an example; use a model ID available to your account.
5. Confirm that Settings reports “Doubao is ready.”
6. Set the translation service to “Doubao (Volcengine Ark),” or leave it on Automatic so Doubao can serve as the fallback when Apple Translation is unavailable.

The API key is stored in macOS Keychain and is not displayed again after it is
saved. Click “Replace API Key” when you need to update it. The model ID and
service selection stay on the current Mac and are not synchronized through
iCloud.

## Use the Translation Board

- Changing the source or target language immediately translates again with the new settings.
- When both source and target languages are explicit, click the swap button or press `T` to exchange them and translate again.
- Changing the service under “More → Translation service” immediately translates again.
- The result preserves line breaks and renders lightweight Markdown such as
  headings, emphasis, lists, quotes, and code. You can also select text or click
  “Copy Translation” to copy the complete, unmodified result.
- Click “Retry” after a failure. If no service is available, open Translation Settings directly from the board.
- Translation, explanation, and full content preview are mutually exclusive. Opening one closes the other two.
- Press `Esc`, click outside the board, click its close button, or press the global translation shortcut again to dismiss it.

## Privacy

- With Apple Translation, Pesty submits the current text through the system Translation framework.
- With Doubao, only the text you explicitly ask Pesty to translate, including transient locally recognized OCR text, is sent to Volcengine Ark.
- Image OCR runs entirely on the Mac. Pesty does not upload the original image or persist OCR output to clipboard history or iCloud.
- Global translation first tries to read selected text through Accessibility. If an app does not expose its selection directly, Pesty may issue a temporary Copy command and then fully restore the original clipboard. The temporary text is not written to history.
- Pesty does not read or translate content from secure text fields.
- The Doubao API key is stored in macOS Keychain, not in preferences, clipboard storage, or iCloud.
- The translated result is written to the system clipboard only when you click “Copy Translation.”

For more information about data handling, see [Privacy](PRIVACY.md).

## Troubleshooting

### Pesty asks you to select text first

Pesty did not detect a text selection in the active app. Select the text again
and press the global translation shortcut. Some apps do not expose their
selection through Accessibility, so Pesty attempts a safe copy fallback. If
the app also blocks copying, Pesty cannot read the selection.

### Pesty requires Accessibility permission

Open “System Settings → Privacy & Security → Accessibility,” enable Pesty, and
try again.

### Pesty asks you to select a text clip

The current Pesty card contains no translatable text. Select a text, rich-text,
or text-bearing link card and try again.

### No translation service is available

macOS 14 does not support Apple Translation, so configure Doubao. On macOS 15
or later, select Apple Translate. If it remains unavailable, confirm the macOS
version and try a different language pair.

### Apple Translation language packs are not downloaded

Open “Settings → Translate & Explain,” switch the service to Apple Translate,
and download the “Required baseline” and current language-pair packs. Keep
Settings open while the packs download.

### Doubao asks for an API key and model ID

The API key and model ID must be saved separately. After saving both, confirm
that Settings reports “Doubao is ready.”

### Doubao returns an HTTP error or translation fails

Check the network connection, API key, model ID, account quota, and model
permissions, then click “Retry” in the translation board. Pesty logs never
include the source text, translation, API key, or service response body.

### Apple Translation does not support the language pair

Choose a different source or target language, or configure Doubao and switch
the service to Doubao or Automatic.
