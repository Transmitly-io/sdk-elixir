defmodule Transmitly do
  @moduledoc """
  Dependency-light Elixir client for the Transmitly email API.

      tx = Transmitly.Client.new(System.fetch_env!("TRANSMITLY_API_KEY"))

      accepted =
        Transmitly.Client.send_email(tx, %{
          "from" => "Notify <notify@mail.acme.com>",
          "to" => ["ada@example.net"],
          "subject" => "Your workspace is ready",
          "html" => "<p>Welcome.</p>"
        })
  """

  alias Transmitly.Client

  @doc """
  Verify a webhook delivery. Pass the raw request body, the
  `Transmitly-Signature` header and the endpoint signing secret.
  """
  def verify_webhook(raw_body, signature_header, secret, tolerance \\ 300) do
    Client.verify_webhook(raw_body, signature_header, secret, tolerance)
  end
end
