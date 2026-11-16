# Transmitly Elixir SDK

Elixir client for the Transmitly API.

```elixir
# mix.exs — from the platform repository
{:transmitly, path: "sdk/elixir"}
```

```elixir
tx = Transmitly.Client.new(System.fetch_env!("TRANSMITLY_API_KEY"))

accepted =
  Transmitly.Client.send_email(tx, %{
    "from" => "Notify <notify@mail.acme.com>",
    "to" => ["ada@example.net"],
    "subject" => "Your workspace is ready",
    "html" => "<p>Welcome.</p>",
    "reply_to" => "Support <support@acme.com>",
    "tags" => %{"flow" => "onboarding"}
  })
```

`send_email/3` generates an idempotency key. Pass `idempotency_key:` to control
it yourself; retries with the same key return the original message.

## Phoenix

```elixir
# config/runtime.exs
config :my_app, :transmitly,
  api_key: System.fetch_env!("TRANSMITLY_API_KEY")
```

```elixir
# lib/my_app/mailer.ex
defmodule MyApp.Mailer do
  def welcome(user) do
    tx = Transmitly.Client.new(Application.fetch_env!(:my_app, :transmitly)[:api_key])

    Transmitly.Client.send_email(tx, %{
      "from" => "Notify <notify@mail.acme.com>",
      "to" => [user.email],
      "subject" => "Welcome to Acme",
      "html" => "<p>Your workspace is ready.</p>"
    })
  end
end
```

## Resources

```elixir
Transmitly.Client.get_email(tx, message_id)
Transmitly.Client.list_messages(tx, status: "bounced", limit: 20)
Transmitly.Client.deliveries(tx, message_id)
Transmitly.Client.list_domains(tx)
Transmitly.Client.create_domain(tx, "mail.acme.com")
Transmitly.Client.verify_domain(tx, domain_id)
Transmitly.Client.list_suppressions(tx)
Transmitly.Client.add_suppression(tx, %{"email" => "bounce@example.net", "reason" => "manual"})
Transmitly.Client.list_webhooks(tx)
Transmitly.Client.create_webhook(tx, %{"url" => "https://api.acme.com/hooks", "events" => ["email.delivered_to_mx"]})
Transmitly.Client.inbound_routes(tx)
Transmitly.Client.usage(tx)
Transmitly.Client.events(tx, limit: 50)
Transmitly.Client.health(tx)
```

Non-2xx responses raise `Transmitly.Error` with `status`, `code`, `message`,
`details` and `payload`.

## Webhooks

```elixir
def create(conn, _params) do
  {:ok, raw, conn} = Plug.Conn.read_body(conn)
  signature = Plug.Conn.get_req_header(conn, "transmitly-signature") |> List.first()
  secret = System.fetch_env!("TRANSMITLY_WEBHOOK_SECRET")

  if Transmitly.verify_webhook(raw, signature, secret) do
    # Parse and handle only after the signature passes.
    send_resp(conn, 200, "ok")
  else
    send_resp(conn, 400, "bad signature")
  end
end
```

Domain, webhook and inbound management require an API key with the `admin`
scope.

```bash
mix deps.get
mix test
mix hex.build
```
