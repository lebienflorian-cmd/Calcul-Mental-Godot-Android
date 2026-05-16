# Calcul Mental — Godot 4 / Android

Portage Android (Godot 4 + GDScript) du jeu Pygame "Calcul Mental".
5 modes d'entraînement, profils, sauvegarde JSON, graphique d'historique.

---

## 1. Pré-requis

- **Godot 4.3** (ou plus récent) — version Standard, pas .NET — depuis https://godotengine.org/download
- Pour build Android :
  - **Android Studio** (ou juste les Android SDK + Build Tools)
  - **OpenJDK 17**
  - Un **téléphone Samsung** avec mode développeur activé (ou utiliser un APK installé manuellement)

---

## 2. Ouvrir le projet dans Godot

1. Lance Godot 4.
2. Clique sur **Import**.
3. Sélectionne le fichier `project.godot` à la racine du dossier décompressé.
4. Godot ouvre le projet et importe les ressources.
5. Clique sur le bouton **▶ Play** en haut à droite pour lancer le jeu sur ton PC et vérifier qu'il fonctionne.

---

## 3. Structure du projet

```
calcul_mental/
├── project.godot          ← fichier d'ouverture Godot
├── icon.svg
├── scenes/                ← scènes .tscn
│   ├── Main.tscn
│   ├── MainMenu.tscn
│   ├── GameScene.tscn
│   ├── OptionsScene.tscn
│   ├── PauseOverlay.tscn
│   ├── RulesScene.tscn
│   ├── ScoresScene.tscn
│   └── EndScene.tscn
├── scripts/
│   ├── autoload/          ← singletons globaux
│   ├── scenes/            ← logique de chaque scène
│   └── game_modes/        ← un fichier par mode
└── assets/
    ├── sounds/            ← bruitages .wav (optionnels)
    ├── music/             ← musiques .ogg (optionnelles)
    └── fonts/             ← (vide)
```

---

## 4. Sons et musiques

Les sons sont **optionnels**. Le jeu fonctionne sans, en silence.

Si tu veux ajouter des sons, dépose les fichiers dans :
- `assets/sounds/` : `sfx_click.wav`, `sfx_back.wav`, `sfx_start.wav`, `sfx_end.wav`,
  `sfx_step.wav`, `sfx_anzan.wav`, `sfx_ding.wav`, `sfx_correct.wav`, `sfx_error.wav`,
  `sfx_save.wav`
- `assets/music/` : `music_menu.ogg`, `music_game.ogg`

Sources libres recommandées :
- **freesound.org** (CC0 / CC-BY)
- **opengameart.org**
- **zapsplat.com** (compte gratuit)

---

## 5. Build APK pour Android (Samsung)

### A. Installer les outils

1. Installer **OpenJDK 17** : https://adoptium.net/
2. Installer **Android Studio** : https://developer.android.com/studio
3. Dans Android Studio → SDK Manager, installer :
   - Android SDK Platform 34 (ou plus récent)
   - Android SDK Build-Tools (dernier)
   - Android SDK Command-line Tools
   - Android SDK Platform-Tools

### B. Configurer Godot

1. Dans Godot, ouvre **Editor → Editor Settings → Export → Android**.
2. Renseigne :
   - `Android SDK Path` : le chemin de ton SDK Android (ex: `C:\Users\TonNom\AppData\Local\Android\Sdk`)
   - `Java SDK Path` : le chemin de ton JDK 17
   - `Debug Keystore` : laisse vide pour générer un keystore de debug auto

3. **Télécharger les templates d'export** :
   - Menu **Editor → Manage Export Templates**
   - Clique **Download and Install**

### C. Configurer l'export

1. Menu **Project → Export...**
2. Clique **Add...** → **Android**
3. Dans le panneau de droite :
   - **Architectures** : coche `arm64-v8a` (et `armeabi-v7a` pour vieux téléphones)
   - **Package → Unique Name** : `com.tonpseudo.calculmental`
   - **Permissions** : coche
     - `RECORD_AUDIO` (pour la reconnaissance vocale)
     - `INTERNET` (recommandé, mais pas requis)
   - **Screen → Orientation** : `Portrait` (recommandé) ou `Sensor`

4. **Export Project** → choisis un emplacement et un nom (`calcul_mental.apk`).

### D. Installer l'APK sur ton Samsung

**Méthode 1 — Câble USB** :
1. Active le **mode développeur** sur ton Samsung :
   - Réglages → À propos du téléphone → Informations sur le logiciel
   - Tape 7 fois sur **Numéro de version**
2. Réglages → Options de développement → **Débogage USB** : activé
3. Branche le téléphone, accepte la demande d'autorisation.
4. Dans Godot, dans la fenêtre d'export, ton téléphone apparaît dans la liste — clique **One-click deploy**.

**Méthode 2 — Transfert manuel** :
1. Copie le fichier `.apk` sur ton téléphone (USB, email, Google Drive…).
2. Sur le téléphone, ouvre le fichier APK.
3. Android te dira « source inconnue » — autorise l'installation pour ton explorateur de fichiers.
4. L'app s'installe.

---

## 6. Voix (TTS et STT) sur Android

### TTS — Synthèse vocale
Fonctionne **out-of-the-box** sur Android : Godot 4 utilise l'API `TextToSpeech` native d'Android. Aucune config supplémentaire.

### STT — Reconnaissance vocale
Godot n'intègre pas la reconnaissance vocale Android nativement. Deux options :

**Option A — Plugin Godot Android (recommandée)** :
- Cherche un plugin tiers Godot 4 pour `SpeechRecognizer` sur GitHub (ex: `godot-android-speech`).
- Suis les instructions pour l'intégrer dans `android/plugins/`.
- Le code dans `voice_manager.gd` détecte automatiquement le singleton Android s'il est présent.

**Option B — Désactiver le STT** :
- Dans Options du jeu, désactive « Réponse vocale ».
- Saisis tes réponses au clavier numérique tactile (déjà inclus).

Sans plugin STT, le bouton micro 🎤 ne fait rien — mais tout le reste marche.

---

## 7. Modes de jeu (rappel)

| Mode | Description |
|---|---|
| **Contre-la-montre** | Maximum de calculs en N secondes |
| **Série chronométrée** | N calculs, temps total mesuré |
| **Flash Anzan** | Nombres affichés successivement, donner la somme |
| **Mode audio** | Calcul lu vocalement, réponse vocale ou tactile |
| **Calcul Infernal** | n-back : répondre au calcul d'il y a N tours |

---

## 8. Contrôles

| Action | Touche / Geste |
|---|---|
| Valider réponse | Bouton ✓ ou Entrée |
| Pause | Bouton ‖ ou Espace |
| Retour menu | Échap |
| Plein écran | F11 / F1 |
| Répéter audio | Q |
| Saisir nombre | Clavier numérique tactile à l'écran |
| Réponse vocale | Maintenir le bouton 🎤 |

---

## 9. Limites connues / TODO

- Pas de plugin STT inclus — à intégrer séparément si tu veux la dictée vocale Android.
- Pas de sons fournis — à ajouter dans `assets/sounds/` et `assets/music/`.
- Les animations sont volontairement plus sobres que la version Pygame (priorité mobile : lisibilité + perf).
- Le générateur de calculs gère les 4 opérations + parenthèses simples ; certaines combinaisons exotiques d'options peuvent retomber sur des cas par défaut.
- Pas de tests automatisés.

---

## 10. Tester rapidement sur PC

1. Ouvre le projet dans Godot.
2. Clique sur ▶ Play (en haut à droite).
3. Le menu apparaît. Clique **Jouer** → tu joues en mode Contre-la-montre par défaut.
4. Va dans **Options** pour changer le mode, la difficulté, etc.

Bon entraînement !
