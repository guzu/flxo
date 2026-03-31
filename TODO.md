# FlxO — Pistes d'amélioration

## Gains rapides (backend déjà prêt)

- [ ] **Export ICS** — `GET /presence/me/ics` existe, il manque un bouton dans la topbar ; idéalement URL avec token en query param pour s'abonner depuis un client calendrier
- [x] **Bureaux génériques** — `desks.js` supprimé ; le nombre de bureaux vient du backend (comptage SQL des `Seat` par office via `GET /auth/config`) ; les IDs `desk1`..`deskN` sont dérivés automatiquement
- [ ] **Attributs des bureaux** — CRUD `/property/{seat_id}/{name}` dispo ; charger depuis la base et afficher dans le tooltip du plan SVG
- [ ] **Désactivation de compte** — champ `disabled` existe sur `User` mais ignoré ; ajouter "Désactiver" en alternative douce à la suppression

## UX à fort impact

- [x] **Résumé par créneau** — ligne "Présents" au-dessus de "Mon poste", comptage des confirmés par slot ; toggle via bouton 123 dans la ligne semaine, état persisté dans `localStorage`
- [ ] **Toasts d'erreur** — les erreurs API font un rollback silencieux ; afficher un message discret en bas de page
- [x] **Réservation de bureau par créneau** — ligne "Mon poste" dans la grille, popup `DeskPickerModal` sur plan SVG, `seat_id` sauvegardé par présence, postes pris visibles dans la popup, triangle indicateur sur les cellules des collègues, option "appliquer à toutes mes réservations futures"
- [x] **Conflits de bureau sur le plan principal** — `FloorPlan.vue` reflète les réservations par créneau au survol d'une cellule de la grille (desk-slot ou SlotCell) ; les bureaux occupés sont colorés avec le nom de l'occupant en tooltip
- [ ] **Copier une semaine** — bouton "Reproduire sur la semaine suivante" (N POST séquentiels)

## Nouvelles fonctionnalités

- [ ] **Synchronisation périodique** — polling toutes les 60s pour voir les réservations des collègues en temps réel, avec merge intelligent dans le state local
- [ ] **Réservations récurrentes** — "tous les lundis matin pendant 4 semaines", résumé avant confirmation
- [x] **Multi-office** — `OfficePicker` dans la sidebar, `switchOffice()` met à jour les préférences bureau, les bookings portent un `officeId`, indicateur de conflit cross-office (point coloré) dans `SlotCell`
- [ ] **Vue mobile** — la grille 2 sem × N personnes × 10 colonnes est inexploitable sur téléphone

## Administration

- [ ] **Notion d'admin** — ajouter un champ `is_admin: bool` sur `User` (migration Alembic) ; pour l'instant tous les utilisateurs sont admin ; protéger les routes d'admin avec une dependency `require_admin` ; afficher un indicateur visuel dans la topbar
- [ ] **Interface d'administration** — page/onglet Admin accessible aux admins ; permet de gérer :
  - **Lieux** (`Office`) : créer, renommer, supprimer ; upload optionnel d'un SVG de plan de salle
  - **Salles** (`Seat`) : ajouter/renommer/supprimer des salles dans un lieu ; un lieu peut avoir N salles sans SVG (liste simple) ou avec SVG (plan interactif comme Wojo Paris) ; attributs libres sur chaque salle (`Property`)
  - Les bureaux ne sont plus hardcodés (`desk_count` dans config) ; reste à gérer dynamiquement les salles depuis l'interface admin

## Performance (scalabilité à ~100 places)

- [x] **`limit=500` sur les présences** (bug) — `apiListPresences` pagine automatiquement par pages de 500 jusqu'à épuisement
- [ ] **Création des sièges 1 par 1** — `initApp()` fait un `POST /seat/` séquentiel par bureau manquant ; avec 100 places × N offices = centaines d'appels au premier lancement. Solution : endpoint bulk `POST /seat/bulk` ou seed côté backend
- [ ] **"Appliquer à tous" séquentiel** — `setSlotDesk` avec l'option "appliquer à tous" fait un `PUT /presence/{id}` par créneau futur, séquentiellement (contrainte SQLite). Avec 100 créneaux = 100 PUT séquentiels. Solution : endpoint bulk `PUT /presence/bulk-seat`
- [x] **Recherches linéaires dans `bookings[]`** — `_bookingMap` (Map) indexée par `"personId|weekKey|day|slot"` ; lookups en O(1) au lieu de `.find()` linéaires ; batch loading avec notification réactive unique
- [x] **`GET /seat/` sans filtre office** — `initApp()` utilise `apiListOfficeSeatsPaginated(officeId)` via `GET /office/{id}/seats` (paginé, par office) ; limite backend augmentée à 500
- [ ] **`overbookedSlots` computed** — itère sur tous les bookings à chaque changement ; mineur seul mais déclenché fréquemment

## Qualité technique

- [ ] **Tests backend** — aucun test malgré la CI ; priorité : overlap check, `delete_user` cascade, validators
- [ ] **TypeScript frontend** — `state.js` et `api.js` sans types ; migration progressive
- [ ] **Bug backend** — `session.refresh()` échoue sporadiquement sur `Presence` (`InvalidRequestError: Could not refresh instance`) ; contourné côté frontend par des appels séquentiels ; à corriger en utilisant `session.get()` plutôt que `session.exec(select(...))` dans `get_presence`
