# Alusekis API v1

Serveris: `server/` (ASP.NET Core, `Alusekis.Api`). Šis dokumentas – sutartis tarp serverio ir mobiliosios programėlės.

**Būsena:** ✅ įgyvendinta · 🕓 suplanuota (T0 sukurtas tik karkasas; endpoint'ų formos gali dar keistis, kol neįgyvendinti).

## Bendros taisyklės

| Tema | Taisyklė |
|---|---|
| Bazinis kelias | `/api/v1` (išskyrus `GET /health`) |
| Formatas | JSON, `Content-Type: application/json; charset=utf-8`, laukai `camelCase` |
| Datos | UTC, ISO 8601 su `Z`, pvz. `2026-11-20T18:30:00Z` |
| Kainos | sveiki centai `priceCents`, 1–50000 (0,01–500,00 €) |
| Talpa | sveiki mililitrai `volumeMl`, 1–50000 |
| ID | `long` (64 bitų sveikas skaičius) |
| Enum'ai | eilutės: `Role` = `Guest`/`User`/`Admin`; `PriceStatus` = `Pending`/`Approved`/`Rejected`; `ReportReason` = `WrongPrice`/`DifferentProduct`/`OutdatedData`/`Other`; `ReportStatus` = `New`/`Confirmed`/`Rejected` |
| Autentifikacija | `Authorization: Bearer <token>` (✅) |
| Idempotentiškumas | rašymo užklausoms `Idempotency-Key: <uuid>`; pakartota užklausa su tuo pačiu raktu grąžina pirminį atsakymą (🕓) |
| Užklausos ID | `X-Request-Id` grąžinamas kiekviename atsakyme; klientas gali atsiųsti savo (iki 64 simb., `A-Z a-z 0-9 - _ . :`) |
| Laiko limitas | serveris užklausą apdoroja ne ilgiau kaip 10 s, kitaip `504 request_timeout` |

### Klaidos

Visos klaidos turi vienodą formą:

```json
{
  "code": "not_found",
  "message": "The requested resource was not found.",
  "requestId": "0HNQ98LI8J140:00000002"
}
```

| HTTP | `code` |
|---|---|
| 400 | `bad_request` |
| 401 | `unauthorized` |
| 403 | `forbidden` |
| 404 | `not_found` |
| 405 | `method_not_allowed` |
| 409 | `conflict` (registracijai – `email_taken`) |
| 422 | `validation_failed` (autentifikacijai – `email_invalid`, `password_length_invalid`) |
| 429 | `too_many_requests` |
| 500 | `internal_error` |
| 503 | `service_unavailable` |
| 504 | `request_timeout` |

---

## Sistema

### ✅ `GET /health`
Serverio ir DB būsena. `200` – sveika, `503` – ne.

```json
{
  "status": "Healthy",
  "checks": {
    "server": { "status": "Healthy", "description": null },
    "database": { "status": "Healthy", "description": "Database is reachable and up to date." }
  },
  "checkedAt": "2026-11-23T09:38:45.4659974Z"
}
```

### ✅ `GET /api/v1/ping`
```json
{ "status": "ok", "serverTime": "2026-11-23T09:37:29.9521625Z" }
```

---

## ✅ Autentifikacija (NI-01)

Prieigos raktas – atsitiktinis 256 bitų raktas, DB saugoma tik jo SHA-256 maiša. Galioja **30 min.** nuo išdavimo (be pratęsimo); serveris kiekvienoje autentifikuotoje užklausoje tikrina sesiją DB. Slaptažodžiai – `PasswordHasher<User>` (PBKDF2 + druska). Rolės: `Guest` (neprisijungęs, tik peržiūra), `User` (keičia duomenis), `Admin` (valdo katalogą) – tikrinamos tik serveryje (policy `RequireUser`, `RequireAdmin`).

Nauji klaidų kodai: `email_invalid` (422), `email_taken` (409), `password_length_invalid` (422), `invalid_credentials` (401), `invalid_password` (403), `invalid_reset_token` (400). Visada grąžinamas vienas kodas (pirmas rastas: el. paštas, tada slaptažodis).

### `POST /api/v1/auth/register`
```json
// užklausa: el. paštas ≤ 254 simb., slaptažodis 12–128 simb.
{ "email": "jonas@example.com", "password": "********" }
```
```json
// 201
{
  "user": { "id": 2, "email": "jonas@example.com", "displayName": "jonas", "role": "User" },
  "token": "<opaque>",
  "expiresAt": "2026-11-23T10:30:00Z"
}
```
`422 email_invalid` / `422 password_length_invalid`; `409 email_taken` – el. paštas (be didžiųjų raidžių ir tarpų skirtumo) jau užimtas.

### `POST /api/v1/auth/login`
```json
{ "email": "jonas@example.com", "password": "********" }
```
`200` – kaip registracijos. Bet kokia klaida (nėra paskyros / blogas slaptažodis) – vienodas `401 invalid_credentials`. Po 5 nesėkmingų bandymų vienai paskyrai per 15 min. – `429 too_many_requests` su `Retry-After` (sekundėmis), net jei slaptažodis teisingas.

### `POST /api/v1/auth/logout` (prisijungus)
Atšaukia šią sesiją (`RevokedAt`). `204`. Tas pats raktas toliau grąžina `401 unauthorized`.

### `GET /api/v1/auth/me` (prisijungus)
```json
{ "id": 2, "email": "jonas@example.com", "displayName": "jonas", "role": "User" }
```

### `POST /api/v1/auth/forgot-password`
```json
{ "email": "jonas@example.com" }
```
Visada `202` (neatskleidžia, ar paskyra yra); `422 email_invalid` tik blogam formatui. Sukuriamas vienkartinis raktas (galioja 30 min., DB – tik maiša) ir per `IEmailSender` išsiunčiama nuoroda `alusekis://reset-password?token=...`. Kol nėra SMTP, nuoroda išvedama į serverio žurnalą (`ConsoleEmailSender`).

### `POST /api/v1/auth/reset-password`
```json
{ "token": "<iš nuorodos>", "newPassword": "********" }
```
`204` – slaptažodis pakeistas, raktas panaudotas, visos sesijos atšauktos. `400 invalid_reset_token` – raktas neteisingas, pasibaigęs ar jau panaudotas; `422 password_length_invalid`.

### `DELETE /api/v1/auth/account` (prisijungus)
```json
{ "password": "********" }
```
`204` – paskyra ir sesijos ištrintos; kainos, produktai ir pranešimai lieka be nuorodos į asmenį; sukuriamas `DeletionMarker` (`User`, id) ir audito įrašas be asmens duomenų. Blogas slaptažodis – `403 invalid_password` (ne 401, kad klientas neatjungtų vartotojo); bandymai skaičiuojami į tą patį 5/15 min. limitą.

---

## Parduotuvės (NI-02: `cities` ir `stores` ✅, `stores/{id}/prices` 🕓)

Prisijungti nereikia (leidžiama svčiui). Vietos duomenys naudojami tik vienai paieškai: nesaugomi ir nelogginami.

### ✅ `GET /api/v1/cities`
Miestų sąrašas pagal pavadinimą.
```json
{ "items": [ { "id": 2, "name": "Kaunas" }, { "id": 3, "name": "Klaipėda" }, { "id": 1, "name": "Vilnius" } ] }
```

### ✅ `GET /api/v1/stores`
Vienas iš dviejų režimų:

| Režimas | Parametrai | Rikiavimas |
|---|---|---|
| Netoliese | `lat` (−90…90), `lng` (−180…180), `radiusKm` (sveikas 1–50) – visi trys | pagal atstumą (Haversine), artimiausia pirma; yra `distanceKm` |
| Pagal miestą | `cityId` | pagal pavadinimą; `distanceKm` nėra |

Blogos reikšmės, abu režimai kartu, nė vieno ar ne visi trys GPS parametrai – `422 validation_failed`; neskaitomas skaičius (pvz. `lat=abc`) – `400 bad_request`. Parduotuvių nerasta (ar nezinomas `cityId`) – `200` su tuščiu `items`. Daugiausia 200 įrašų.
```json
{
  "items": [
    {
      "id": 2,
      "name": "Rimi Hyper",
      "address": "Ozo g. 25",
      "latitude": 54.7117,
      "longitude": 25.2827,
      "distanceKm": 3.67,
      "city": { "id": 1, "name": "Vilnius" }
    }
  ]
}
```
Seed koordinatės yra apytikslės (iki kvartalo tikslumo).

### `GET /api/v1/stores/{storeId}/prices`
Naujausia patvirtinta (`Approved`) kiekvieno produkto kaina parduotuvėje.
```json
{
  "store": { "id": 1, "name": "Maxima XX", "address": "Ukmergės g. 282" },
  "items": [
    {
      "priceEntryId": 41,
      "product": { "id": 1, "name": "Švyturys Ekstra", "brand": "Švyturys", "volumeMl": 500 },
      "priceCents": 149,
      "observedAt": "2026-10-30T09:00:00Z"
    }
  ]
}
```

---

## Produktai 🕓

### `GET /api/v1/products/search?q=svyturys&volumeMl=500&limit=20`
`q` – privalomas (min. 2 simboliai); paieška nejautri didžiosioms raidėms ir diakritikams (`svyturys` randa „Švyturys“). `volumeMl`, `limit` (1–50, numatyta 20) – neprivalomi.
```json
{
  "items": [
    { "id": 1, "name": "Švyturys Ekstra", "brand": "Švyturys", "volumeMl": 500 },
    { "id": 3, "name": "Švyturys Baltijos", "brand": "Švyturys", "volumeMl": 500 }
  ]
}
```

### `POST /api/v1/products` (prisijungus)
```json
// užklausa (+ Idempotency-Key)
{ "name": "Dundulis Kvietinis", "brand": "Dundulis", "volumeMl": 500 }
```
```json
// 201
{ "id": 31, "name": "Dundulis Kvietinis", "brand": "Dundulis", "volumeMl": 500, "createdAt": "2026-11-23T10:00:00Z" }
```
`409 conflict` – produktas su tuo pačiu normalizuotu pavadinimu ir talpa jau yra.

### `GET /api/v1/products/{productId}/compare?cityId=1`
Naujausia patvirtinta produkto kaina kiekvienoje parduotuvėje, pigiausia pirma.
```json
{
  "product": { "id": 1, "name": "Švyturys Ekstra", "brand": "Švyturys", "volumeMl": 500 },
  "items": [
    {
      "store": { "id": 4, "name": "Lidl", "address": "Kalvarijų g. 202", "cityId": 1 },
      "priceEntryId": 52,
      "priceCents": 139,
      "observedAt": "2026-10-28T15:00:00Z"
    },
    {
      "store": { "id": 1, "name": "Maxima XX", "address": "Ukmergės g. 282", "cityId": 1 },
      "priceEntryId": 41,
      "priceCents": 149,
      "observedAt": "2026-10-30T09:00:00Z"
    }
  ]
}
```

### `GET /api/v1/products/{productId}/history?storeId=1&limit=50&before=41`
Produkto kainų istorija, naujausios pirma. `storeId` neprivalomas; `before` – puslapiavimas pagal `priceEntryId` (grąžinamas kaip `nextBefore`, `null` – daugiau nėra).
```json
{
  "items": [
    { "priceEntryId": 41, "storeId": 1, "priceCents": 149, "status": "Approved", "observedAt": "2026-10-30T09:00:00Z" },
    { "priceEntryId": 17, "storeId": 1, "priceCents": 145, "status": "Approved", "observedAt": "2026-10-12T21:00:00Z" }
  ],
  "nextBefore": null
}
```

---

## Kainos 🕓

### `POST /api/v1/prices` (prisijungus)
Kainų istorija nekeičiama – kiekviena pateikta kaina yra naujas įrašas.
```json
// užklausa (+ Idempotency-Key)
{ "productId": 1, "storeId": 1, "priceCents": 155, "observedAt": "2026-11-23T08:45:00Z" }
```
```json
// 201
{
  "id": 61,
  "productId": 1,
  "storeId": 1,
  "priceCents": 155,
  "status": "Pending",
  "observedAt": "2026-11-23T08:45:00Z",
  "createdAt": "2026-11-23T08:46:02Z"
}
```
`422 validation_failed` – kaina už 1–50000 ribų, `observedAt` ateityje ir pan.; `404 not_found` – nėra produkto ar parduotuvės.

---

## Pranešimai apie klaidas 🕓

### `POST /api/v1/reports` (prisijungus)
```json
// užklausa (+ Idempotency-Key)
{ "priceEntryId": 41, "reason": "OutdatedData", "comment": "Kaina jau 1,69 €" }
```
```json
// 201
{ "id": 7, "priceEntryId": 41, "reason": "OutdatedData", "status": "New", "submittedAt": "2026-11-23T09:10:00Z" }
```

### `GET /api/v1/reports?status=New&limit=50` (Admin)
```json
{
  "items": [
    {
      "id": 7,
      "priceEntryId": 41,
      "reason": "OutdatedData",
      "comment": "Kaina jau 1,69 €",
      "status": "New",
      "reporterUserId": 2,
      "submittedAt": "2026-11-23T09:10:00Z"
    }
  ]
}
```

### `PATCH /api/v1/reports/{reportId}` (Admin)
```json
// užklausa
{ "status": "Confirmed" }
```
```json
// 200
{ "id": 7, "status": "Confirmed", "resolvedAt": "2026-11-23T11:00:00Z", "resolvedByUserId": 1 }
```

---

## Vietinis paleidimas

```bash
cd server
dotnet run --project src/Alusekis.Api            # Development: SQLite failas, auto-migracija
dotnet run --project src/Alusekis.Api -- seed    # bandomieji duomenys (pakartotinai saugu)
dotnet test
```

Konfigūracija – `appsettings*.json`, perrašoma aplinkos kintamaisiais:

| Nustatymas | Aplinkos kintamasis | Būtinas |
|---|---|---|
| `ConnectionStrings:Default` | `ConnectionStrings__Default` | taip – be jo serveris nepasileidžia |
| `Database:MigrateOnStartup` | `Database__MigrateOnStartup` | ne (numatyta `false`, Development – `true`) |

Bandomoji paskyra po seed: `test@alusekis.local` (rolė `User`, slaptažodis nenustatytas – prisijungti negalima; norint turėti paskyrą su slaptažodžiu, užsiregistruokite arba pasinaudokite `forgot-password`, nuoroda bus serverio žurnale).
