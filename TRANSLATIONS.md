# Translations

PocketMesh supports multiple languages through iOS localization. This document explains how the system works and how to contribute translations.

## Supported Languages

| Language   | Code | Status |
|------------|------|--------|
| English    | en   | Complete (source) |
| German     | de   | AI-translated |
| Dutch      | nl   | AI-translated |
| Polish     | pl   | AI-translated |
| Russian    | ru   | AI-translated |
| Ukrainian  | uk   | AI-translated |
| Spanish    | es   | AI-translated |
| French     | fr   | AI-translated |

Languages marked "AI-translated" were generated using AI and may contain errors. Native speaker verification is welcome.

## File Structure

Localization files are organized by feature under `PocketMesh/Resources/Localization/`:

```
Localization/
  en.lproj/           # English (source language)
    Localizable.strings       # Common strings (buttons, tabs, errors)
    Localizable.stringsdict   # Pluralization rules for common strings
    Chats.strings             # Chat feature
    Chats.stringsdict         # Pluralization for chat feature
    Contacts.strings          # Contacts and nodes
    Map.strings               # Map feature
    Onboarding.strings        # Onboarding flow
    Settings.strings          # Settings screens
    Tools.strings             # Tools feature
    RemoteNodes.strings       # Remote nodes feature
  de.lproj/           # German
  nl.lproj/           # Dutch
  ...                 # Other languages
```

## How to Improve Existing Translations

1. Find the language folder (e.g., `de.lproj` for German)
2. Open the relevant `.strings` file
3. Edit the translation value (right side of `=`)
4. Submit a pull request

Example correction in `de.lproj/Settings.strings`:
```
/* Before */
"settings.title" = "Einstellungen";

/* After - if you found a better translation */
"settings.title" = "Konfiguration";
```

Keep the key (left side) unchanged. Only modify the value.

## How to Add Missing Translations

If a string shows in English when using another language, the translation is missing.

1. Find the key by searching English `.strings` files for the text
2. Add the key with your translation to the corresponding file in your language folder
3. Submit a pull request

## How to Request a New Language

Open an issue with:
- Language name and ISO 639-1 code (e.g., "Japanese - ja")
- Whether you can help verify translations

We can generate AI translations for new languages, but native speaker verification improves quality significantly.

## For Developers: Adding New Strings

### Step 1: Add to English .strings File

Add your string to the appropriate feature file in `en.lproj/`:

```
/* Location: MyView.swift - Purpose: Button to submit form */
"myFeature.submitButton" = "Submit";
```

Include a comment with file location and purpose.

### Step 2: Use the Generated Constant

SwiftGen generates type-safe constants. After building, use:

```swift
// For Localizable.strings
L10n.Localizable.Common.ok

// For feature-specific files
L10n.Chats.Conversation.sendButton
L10n.Settings.Account.title
```

### Step 3: Add Translations

Add the same key to all other language files. You can use AI translation as a starting point, but mark it for review:

```
/* Location: MyView.swift - Purpose: Button to submit form */
/* AI-translated - please verify with native speakers. */
"myFeature.submitButton" = "Absenden";
```

## Pluralization

Use `.stringsdict` files for strings that change based on quantity.

### Simple Languages (English, German, Dutch, Spanish, French)

These languages use two forms: `one` (exactly 1) and `other` (0, 2+).

```xml
<key>items.count</key>
<dict>
    <key>NSStringLocalizedFormatKey</key>
    <string>%#@count@</string>
    <key>count</key>
    <dict>
        <key>NSStringFormatSpecTypeKey</key>
        <string>NSStringPluralRuleType</string>
        <key>NSStringFormatValueTypeKey</key>
        <string>d</string>
        <key>one</key>
        <string>%d item</string>
        <key>other</key>
        <string>%d items</string>
    </dict>
</dict>
```

### Slavic Languages (Polish, Russian, Ukrainian)

These languages have complex plural rules with four forms:

| Form | Polish Example | Numbers |
|------|----------------|---------|
| one | 1 wiadomosc | 1 |
| few | 2-4 wiadomosci | 2-4, 22-24, 32-34... |
| many | 5-21 wiadomosci | 0, 5-21, 25-31... |
| other | 1.5 wiadomosci | Fractions |

Example for Russian:
```xml
<key>one</key>
<string>%d сообщение</string>
<key>few</key>
<string>%d сообщения</string>
<key>many</key>
<string>%d сообщений</string>
<key>other</key>
<string>%d сообщений</string>
```

## Testing Translations

1. Build the app
2. Change the simulator/device language in Settings
3. Launch PocketMesh and verify strings appear correctly

For German translations, test at the largest Dynamic Type size since German words are often longer than English.

## Questions

Open an issue for translation questions or to report incorrect translations.
