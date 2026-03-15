# FlxO Frontend — frontend-poc

Prototype Vue 3 de réservation de bureaux, connecté au backend FastAPI.

## Stack

- **Vite + Vue 3** (Composition API, `<script setup>`)
- CSS intégré dans les composants (scoped), pas de framework CSS
- État réactif global dans `src/state.js` (pas de store externe)
- API backend via `src/api.js` (token Bearer, localStorage)

## Structure

```
src/
├── main.js              # Point d'entrée
├── App.vue              # Gate login + layout principal (sidebar + grille)
├── state.js             # État réactif global (auth, personnes, réservations, semaine)
├── api.js               # Couche HTTP vers le backend
├── colors.js            # Palette de couleurs auto-attribuées
├── (desks removed — desk count from backend DB via /auth/config)
└── components/
    ├── LoginView.vue    # Formulaire de connexion
    ├── FloorPlan.vue    # Plan SVG interactif (clic bureau = attribution), max-height 300px
    ├── WeekGrid.vue     # Grille 2 semaines côte à côte (semaine courante + suivante)
    ├── WeekNav.vue      # Navigation semaine : bouton calendrier SVG + chevrons SVG
    ├── PersonRow.vue    # Ligne personne dans la grille (clic + drag-select)
    ├── SlotCell.vue     # Cellule AM/PM cliquable
    └── PersonForm.vue   # Formulaire ajout personne (username + password)
```

## Commandes

```bash
npm run dev    # serveur de développement → http://localhost:5173
npm run build  # build production dans dist/
```

## Configuration

`VITE_API_URL=http://localhost:8000` dans `.env.development`

## Comportements clés

- **Auth** : token JWT dans `localStorage` (`flxo_token`), auto-login au rechargement
- **Semaines passées** : grille en lecture seule, opacité réduite
- **Jours passés** (semaine courante) : cellules grisées, non interactives
- **Grille** : toujours 2 semaines affichées (offset courant + offset+1), séparateur épais entre les deux
- **Navigation** : `navigateWeek(delta)` — charge lazily les semaines non encore fetchées
- **Bookings** : optimistic updates avec rollback sur erreur API
- **Seuls ses propres créneaux** : guard `isLoggedUser` dans `PersonRow.vue`
- **Drag-select** : cliquer-glisser sur les cellules pour réserver plusieurs créneaux d'un coup
- **Commentaire** : point rose sur l'icône bulle quand un commentaire est saisi, sync backend debounce 800ms
- **États d'une cellule** : 3 états cycliques au clic — confirmé (✓, fond plein), peut-être (?, fond léger + bordure), vide
- **Lignes vides** : la grille affiche toujours au minimum `deskCount` lignes ; les places non occupées sont rendues en gris clair, sans interaction
- **Filtrage des personnes** : seules les personnes ayant au moins un booking présent ou futur (`weekKey >= semaine courante`) sont affichées ; l'utilisateur connecté est toujours visible

## Conventions

- Langue de l'UI : français
- Commits en anglais (`--no-verify` requis, le hook vérifie l'email Vates)
- Le SVG source est `wojo-paris.svg` (racine), copié dans `public/` pour le serveur
- `wojo-logo.png` (racine) et `public/wojo-logo.png` doivent être identiques (version rognée)
- Les bureaux ont des IDs `desk1` à `desk6` dans le SVG
- `getTodayDayIndex(offset)` dans `state.js` : retourne l'index du jour courant (0=lundi, 4=vendredi, -1=semaine future, 5=semaine passée/weekend)
- `base: './'` dans `vite.config.js` — tous les chemins du build sont relatifs (déploiement statique)
- Le fetch du SVG utilise `import.meta.env.BASE_URL` pour être compatible avec n'importe quel chemin de déploiement
