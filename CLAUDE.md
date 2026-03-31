# FlxO — Réservation de bureaux flex

Application de réservation de bureaux en coworking (Wojo Paris).

## Structure

```
backend/          # FastAPI + SQLModel + Alembic (Python)
frontend/         # Vue 3 + Vite
docker-compose.yml
```

## Lancer le projet

```bash
# Backend (depuis backend/)
uv run uvicorn flxo.api.main:app --reload
# → http://localhost:8000, docs → http://localhost:8000/docs

# Frontend (depuis frontend/)
npm run dev
# → http://localhost:5173
```

## Git

- Commits en **anglais**
- Hook de pre-commit vérifie l'email → utiliser `--no-verify`
- Branche principale : `master`

---

## Backend

**Stack :** Python 3.12+, FastAPI, SQLModel (≥0.0.27), Alembic, uv
**DB :** SQLite (dev) ou PostgreSQL (prod). Config via `config.toml` ou `FLXO__*` env vars.

### Architecture

```
flxo/
├── api/
│   ├── main.py              # App FastAPI, CORS, enregistrement des routers
│   ├── routers/             # auth, user, presence, office, seat, property
│   └── dependencies/        # database.py (SessionDep), user.py (UserDep), settings.py (SettingsDep)
├── models/                  # SQLModel : Base → DTO → Public → Table (héritage linéaire)
├── services/                # BaseService + UserService, PresenceService, ...
└── core/                    # settings.py, exceptions.py, security.py
```

### Endpoints principaux

| Méthode | Route | Auth | Notes |
|---|---|---|---|
| POST | `/auth/token` | non | Login password → JWT |
| GET | `/auth/oauth2` | non | Redirect OAuth2/Keycloak |
| GET | `/auth/oauth2/callback` | non | Callback SSO |
| GET | `/auth/config` | non | `{ sso_enabled: bool, offices: [{id, name, address, logo_url, floor_plan_url, desk_count}] }` — offices from DB, `logo_url`/`floor_plan_url` from `properties` JSON, `desk_count` from seat count |
| GET | `/user/` | oui | Liste utilisateurs |
| GET | `/user/me` | oui | Profil connecté |
| PATCH | `/user/me` | oui | Mise à jour profil (`UserMeDTO` : `username`, `favorite_seat_id`) |
| POST | `/user/` | oui | Création — **refusé si SSO actif** |
| DELETE | `/user/{id}` | oui | Suppression — **refusé si SSO actif**, cascade presences |
| GET | `/presence/` | oui | Toutes les présences (`PresenceWithUser`) |
| POST | `/presence/` | oui | Créer une présence (créneau unique par user/date/slot) |
| PUT | `/presence/{id}` | oui | Modifier (date, slot, state, seat_id, office_id) |
| DELETE | `/presence/{id}` | oui | Supprimer |
| GET | `/seat/` | oui | Liste des bureaux |
| POST | `/seat/` | oui | Créer un bureau |
| GET | `/office/` | non | Liste des offices |
| GET | `/office/{id}/seats` | oui | Liste paginée des sièges d'un office |
| POST | `/office/` | non | Créer un office |

### Modèles importants

**User** : `username`, `favorite_seat_id` (FK seat), `hashed_password`, `disabled`
**Presence** : `date`, `slot` (morning/afternoon), `state` (confirmed/maybe), `seat_id` (FK seat, nullable), `office_id`, `user_id` — contrainte unique `(user_id, date, slot)` (une seule présence par demi-journée, tous offices confondus) + contrainte unique `(seat_id, date, slot)`
**Office** : `name`, `address`
**Seat** : `name`, `office_id`

### SSO

SSO actif quand `settings.oauth.client_id` est non vide.
- `GET /auth/config` → `{ sso_enabled: bool, offices: [...] }` (offices lues depuis la DB, consommé par le frontend au démarrage)
- `require_no_sso` dependency appliquée sur `POST /user/` et `DELETE /user/{id}`
- Connexion SSO via Keycloak : `GET /auth/oauth2` → redirect → callback → JWT

### Patterns importants

- `BaseService.create()` → `session.add` + `session.commit` + `session.refresh`
- `office_svc.get_config_list()` → requête SQL dédiée avec `COUNT + GROUP BY` pour le `desk_count` (pas de selectinload)
- Migrations Alembic : toujours `batch_alter_table` (compatibilité SQLite)
- **Piège** : `"Type | None"` comme string dans `Relationship()` → crash SQLAlchemy mapper. Toujours utiliser `Optional["Type"]`.
- **Piège** : models Pydantic non-table avec forward references sous `TYPE_CHECKING` → erreur de sérialisation au runtime. Mettre l'import hors du bloc `TYPE_CHECKING`.
- **Piège** : SQLite + écritures concurrentes → `InvalidRequestError: Could not refresh instance`. Les appels API qui modifient la DB doivent être séquentiels côté frontend (pas de `Promise.all` sur des PUT/POST).
- `response_model` sur POST/PUT : utiliser `PresencePublic` (pas `Presence` table model)
- `UserDep = Annotated[User, ...]` (pas `UserPublic`) — le service attend le modèle table
- EM101 ruff : ne pas mettre de string literal directement dans `raise` → extraire dans `msg`

### Lint (depuis `backend/`)

```bash
bash lint.sh   # ruff format --check + ruff check + ty check
```

### Migrations

```bash
uv run alembic upgrade head
uv run alembic revision --autogenerate -m "description"
```

---

## Frontend (`frontend/`)

**Stack :** Vue 3 (Composition API, `<script setup>`), Vite
**État global :** `src/state.js` (pas de store externe)
**API layer :** `src/api.js` — token Bearer dans `localStorage` (`flxo_token`)

### Fichiers clés

| Fichier | Rôle |
|---|---|
| `src/api.js` | Toutes les fonctions HTTP ; `apiFetch` injecte le token, lit `.detail` sur erreur, logout sur 401 |
| `src/state.js` | Auth, personnes, bookings, helpers date, `initApp`, `loadPresenceRange`, `navigateWeek` |
| `src/colors.js` | Palette de couleurs ; `colorForUser(backendId)` persiste la couleur dans `localStorage` |
| `src/App.vue` | Topbar logout + gate login + layout ; modale de confirmation suppression |
| `src/components/LoginView.vue` | Formulaire de connexion |
| `src/components/WeekGrid.vue` | Grille 2 semaines ; ligne "Mon poste" par créneau ; modale de sélection de bureau |
| `src/components/PersonRow.vue` | Ligne par utilisateur (click/drag → booking) ; guard `isLoggedUser` |
| `src/components/SlotCell.vue` | Cellule AM/PM ; triangle indicateur bureau collègue ; point coloré si conflit cross-office |
| `src/components/OfficePicker.vue` | Sélecteur d'office dans la sidebar (masqué si un seul office) |
| `src/components/DeskPickerModal.vue` | Popup de sélection de bureau sur plan SVG ; affiche les postes pris par d'autres utilisateurs |
| `src/components/PersonForm.vue` | Formulaire ajout utilisateur (masqué si SSO) |
| `src/components/WeekNav.vue` | Navigation semaines |

### State réactif (`state.js`)

| Export | Type | Rôle |
|---|---|---|
| `authToken` | `ref` | JWT stocké dans localStorage |
| `loggedUser` | `ref` | `UserPublic` de l'utilisateur connecté |
| `offices` | `reactive[]` | Liste des offices `{ id, name, address, logo_url, floor_plan_url, desk_count }` |
| `activeOfficeId` | `ref` | ID de l'office actif (persisté dans `localStorage`) |
| `ssoEnabled` | `ref` | `true` si SSO actif (lu depuis `GET /auth/config`) |
| `isLoading` | `ref` | Chargement initial |
| `persons` | `reactive[]` | Liste locale des utilisateurs |
| `bookings` | `computed[]` | Dérivé de `_bookingMap` (Map interne) ; `{ personId, weekKey, day, slot, state, backendId, seatId, officeId }` |

### Initialisation (`initApp`)

1. `GET /auth/config` → `ssoEnabled`, `offices[]` → liste des offices avec `desk_count` (agrégation SQL)
2. `GET /user/me` → `loggedUser`
3. `activeOfficeId` ← restauré depuis `localStorage` ou `offices[0].id`
4. `GET /office/{id}/seats` (paginé, par office) → charge/crée les sièges, construit les maps `deskToSeatIdByOffice` / `seatToDeskIdByOffice`
5. `GET /user/` → peuple `persons[]`, marque `isLoggedUser`
6. `loadPresenceRange(-4, 9)` → charge les présences DB dans `_bookingMap` (batch, notification unique)

### Comportements clés

- **Bookings** : `_bookingMap` (Map non-réactif) indexée par `"personId|weekKey|day|slot"` pour des lookups O(1) ; `_bookingVersion` (ref compteur) pour la réactivité manuelle ; optimistic updates + rollback sur erreur API
- **Chargement lazy** : `navigateWeek(delta)` ne fetche que les semaines non encore chargées
- **Présences chargées** : `p.user.id` (pas `p.user_id` — `PresenceWithUser` ne contient pas ce champ)
- **Drag-select** : uniquement sur la ligne de l'utilisateur connecté (`isLoggedUser` guard)
- **SSO** : si actif → `PersonForm` masqué, bouton × de suppression masqué
- **Couleurs** : assignées par `colorForUser(backendId)` depuis `colors.js` ; persistées dans `localStorage` (`flxo_colors`) — stables entre les recharges
- **Sélection de bureau** : ligne "Mon poste" dans `WeekGrid` ; clic sur un créneau confirmé → `DeskPickerModal` ; `seat_id` sauvegardé via `PUT /presence/{id}` ; les appels "appliquer à tous" sont séquentiels pour éviter les conflits SQLite
- **Indicateur bureau collègue** : triangle dans le coin bas-droit de `SlotCell` si un collègue a réservé un bureau sur ce créneau (via `getSlotDesk`)
- **Conflit cross-office** : point coloré semi-transparent dans `SlotCell` si la demi-journée est réservée dans un autre office ; tooltip "Réservé à {office}" ; blocage au clic avec message d'erreur
- **Multi-office** : `OfficePicker` dans la sidebar, `switchOffice()` met à jour les préférences bureau, `activeOfficeId` persisté dans `localStorage`
- **Survol desk-slot** : au survol d'une cellule de la ligne "Mon poste", le plan SVG affiche les bureaux occupés pour ce créneau
- **Détection de conflit backend** : `find_conflict()` consolide la vérification de double booking utilisateur + double booking siège en une seule requête SQL avec `or_()`

### Helpers date

- `weekKeyDayToISO(weekKey, day)` → `"YYYY-MM-DD"` (day: 0=lun, 4=ven)
- `isoToWeekKeyDay(isoDate)` → `{ weekKey, day }`
- `getWeekKey(offset)` → `"YYYY-Www"` (semaine ISO)

### Config

- `frontend/.env.development` : `VITE_API_URL=http://localhost:8000`

---

## Utilisateurs de test

5 utilisateurs seedés : Manu, Steeve, Mathieu, Yann, Stan — mot de passe : `Vates`

> Le validateur `validate_password` exigeait ≥8 chars mais faisait `return ValueError(...)` au lieu de `raise` — corrigé. Les mots de passe courts existants restent valides en base.
