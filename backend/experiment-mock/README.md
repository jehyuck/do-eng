# Experiment mock

The server provides deterministic external HTTP dependencies for the image mission experiment.

- `GET /health`
- `GET /api/member/ai`
- `POST /analyze/face`
- `POST /analyze/object`
- `POST /analyze/doodle`
- `PUT /storage/object?key={objectKey}`
- `GET /__storage`
- `GET /__requests`
- `GET /__metrics`
- `POST /__control`
- `POST /__reset`
- `POST /__auth/users`
- `POST /__auth/login`

An Authorization header ending in `experiment-member-{id}` returns that member ID. Other values return `MOCK_MEMBER_ID`, which defaults to `15`.

Example control payload:

```json
{
  "result": true,
  "delayMs": 500,
  "status": 200,
  "storageDelayMs": 100,
  "storageStatus": 200
}
```

This mock is a repeatable local dependency, not evidence of actual S3 behavior. See [`docs/07_experiment_index.md`](../../docs/07_experiment_index.md) for the experiment document roles.

`GET /__requests` returns per-path counts and metadata without retaining image
contents or Authorization values. `POST /__reset` clears these observations

`GET /__metrics` returns only run-resettable aggregate state: `aiInFlight`,
`aiMaxInFlight`, `aiCompleted`, `storageInFlight`, `storageMaxInFlight`, and
`storageCompleted`. It does not retain request bodies.

`GET /__storage` returns only each stored object's key, byte count, and
SHA-256; it never returns image bytes.

For isolated multi-VU success-path preparation, register users before the
measurement window:

```json
POST /__auth/users
{"users":[{"login":"experiment-RUN-u1","memberId":101}]}
```

Then request a mock-issued token for each VU:

```json
POST /__auth/login
{"login":"experiment-RUN-u1"}
```

Registration enables strict auth. In that mode `/api/member/ai` accepts only
tokens issued by this mock. This is controlled test identity setup, not a
model of the product's login or JWT issuance performance.
