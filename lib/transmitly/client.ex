defmodule Transmitly.Client do
  @moduledoc "HTTP client for the Transmitly API."

  alias Transmitly.Error

  @default_base_url "https://transmitly.io"
  @default_timeout 15_000

  defstruct api_key: nil, base_url: @default_base_url, timeout: @default_timeout

  @type t :: %__MODULE__{api_key: String.t(), base_url: String.t(), timeout: non_neg_integer()}

  def new(api_key, base_url \\ @default_base_url, timeout \\ @default_timeout)

  def new(api_key, base_url, timeout) when is_binary(api_key) and api_key != "" do
    %__MODULE__{
      api_key: api_key,
      base_url: String.trim_trailing(base_url, "/"),
      timeout: timeout
    }
  end

  def new(_api_key, _base_url, _timeout) do
    raise ArgumentError, "api_key is required"
  end

  def send_email(%__MODULE__{} = client, payload, opts \\ []) do
    validate_email!(payload)
    key = Keyword.get(opts, :idempotency_key) || new_idempotency_key()
    request(client, :post, "/v1/emails", payload, [], [{"Idempotency-Key", key}])
  end

  def get_email(%__MODULE__{} = client, id), do: request(client, :get, "/v1/emails/#{encode(id)}")
  def list_messages(%__MODULE__{} = client, query \\ []), do: request(client, :get, "/v1/messages", nil, query)
  def get_message(%__MODULE__{} = client, id), do: request(client, :get, "/v1/messages/#{encode(id)}")

  def deliveries(%__MODULE__{} = client, id),
    do: request(client, :get, "/v1/messages/#{encode(id)}/deliveries")

  def list_domains(%__MODULE__{} = client), do: request(client, :get, "/v1/domains")

  def create_domain(%__MODULE__{} = client, domain),
    do: request(client, :post, "/v1/domains", %{"domain" => domain})

  def verify_domain(%__MODULE__{} = client, id),
    do: request(client, :post, "/v1/domains/#{encode(id)}/verify", %{})

  def delete_domain(%__MODULE__{} = client, id),
    do: request(client, :delete, "/v1/domains/#{encode(id)}")

  def list_suppressions(%__MODULE__{} = client, query \\ []),
    do: request(client, :get, "/v1/suppressions", nil, query)

  def add_suppression(%__MODULE__{} = client, input),
    do: request(client, :post, "/v1/suppressions", input)

  def delete_suppression(%__MODULE__{} = client, id),
    do: request(client, :delete, "/v1/suppressions/#{encode(id)}")

  def list_webhooks(%__MODULE__{} = client), do: request(client, :get, "/v1/webhooks")
  def create_webhook(%__MODULE__{} = client, input), do: request(client, :post, "/v1/webhooks", input)

  def delete_webhook(%__MODULE__{} = client, id),
    do: request(client, :delete, "/v1/webhooks/#{encode(id)}")

  def inbound_routes(%__MODULE__{} = client), do: request(client, :get, "/v1/inbound/routes")

  def create_inbound_route(%__MODULE__{} = client, input),
    do: request(client, :post, "/v1/inbound/routes", input)

  def delete_inbound_route(%__MODULE__{} = client, id),
    do: request(client, :delete, "/v1/inbound/routes/#{encode(id)}")

  def usage(%__MODULE__{} = client), do: request(client, :get, "/v1/usage")
  def events(%__MODULE__{} = client, query \\ []), do: request(client, :get, "/v1/events", nil, query)
  def health(%__MODULE__{} = client), do: request(client, :get, "/v1/health", nil, [], [], false)

  def verify_webhook(raw_body, signature_header, secret, tolerance \\ 300) do
    with true <- is_binary(signature_header) and signature_header != "",
         {timestamp, signature} <- parse_signature(signature_header),
         true <- is_integer(timestamp) and is_binary(signature),
         true <- tolerance <= 0 or abs(System.system_time(:second) - timestamp) <= tolerance do
      expected = :crypto.mac(:hmac, :sha256, secret, "#{timestamp}.#{raw_body}") |> Base.encode16(case: :lower)
      secure_compare(signature, expected)
    else
      _ -> false
    end
  end

  defp parse_signature(header) do
    Enum.reduce(String.split(header, ","), {nil, nil}, fn part, {timestamp, signature} ->
      case String.split(String.trim(part), "=", parts: 2) do
        ["t", value] -> {parse_integer(value), signature}
        ["v1", value] -> {timestamp, value}
        _ -> {timestamp, signature}
      end
    end)
  end

  defp parse_integer(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp secure_compare(left, right) when byte_size(left) == byte_size(right) do
    left
    |> :binary.bin_to_list()
    |> Enum.zip(:binary.bin_to_list(right))
    |> Enum.reduce(0, fn {a, b}, acc -> Bitwise.bor(acc, Bitwise.bxor(a, b)) end)
    |> Kernel.==(0)
  end

  defp secure_compare(_left, _right), do: false

  defp request(client, method, path, body \\ nil, query \\ [], headers \\ [], auth \\ true) do
    url = client.base_url <> path <> query_string(query)
    all_headers =
      [{"accept", "application/json"}] ++
        if(auth, do: [{"authorization", "Bearer #{client.api_key}"}], else: []) ++ headers

    header_charlists = Enum.map(all_headers, fn {key, value} -> {to_charlist(key), to_charlist(value)} end)

    request =
      case body do
        nil ->
          {to_charlist(url), header_charlists}

        _ ->
          {to_charlist(url), header_charlists, ~c"application/json", Jason.encode!(body)}
      end

    http_options = [timeout: client.timeout, connect_timeout: client.timeout]

    case :httpc.request(method, request, http_options, body_format: :binary) do
      {:ok, {{_version, status, _reason}, _response_headers, raw}} ->
        payload = decode(raw)
        if status >= 200 and status < 300 do
          payload
        else
          raise_error(status, payload, raw)
        end

      {:error, reason} ->
        raise Error, status: 0, code: "network_error", message: inspect(reason)
    end
  end

  defp decode(""), do: nil

  defp decode(raw) do
    case Jason.decode(raw) do
      {:ok, value} -> value
      {:error, _} -> raise Error, status: 0, code: "invalid_response", message: "Could not decode JSON response"
    end
  end

  defp raise_error(status, payload, raw) do
    error = if is_map(payload), do: Map.get(payload, "error", %{}), else: %{}

    raise Error,
      status: status,
      code: Map.get(error, "code", ""),
      message: Map.get(error, "message", "Request failed (#{status})"),
      details: Map.get(error, "details"),
      payload: raw
  end

  defp query_string([]), do: ""

  defp query_string(query) do
    encoded =
      query
      |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
      |> Enum.map(fn {key, value} -> "#{URI.encode_www_form(to_string(key))}=#{URI.encode_www_form(to_string(value))}" end)

    if encoded == [], do: "", else: "?" <> Enum.join(encoded, "&")
  end

  defp validate_email!(payload) do
    from = Map.get(payload, "from") || Map.get(payload, :from)
    to = Map.get(payload, "to") || Map.get(payload, :to)
    subject = Map.get(payload, "subject") || Map.get(payload, :subject)
    html = Map.get(payload, "html") || Map.get(payload, :html)
    text = Map.get(payload, "text") || Map.get(payload, :text)
    template = Map.get(payload, "template_id") || Map.get(payload, :template_id)

    cond do
      is_nil(from) or from == "" -> raise ArgumentError, "from is required"
      is_nil(to) or to == [] or to == "" -> raise ArgumentError, "to is required"
      is_nil(subject) or subject == "" -> raise ArgumentError, "subject is required"
      is_nil(html) and is_nil(text) and is_nil(template) -> raise ArgumentError, "html, text or template_id is required"
      true -> :ok
    end
  end

  defp new_idempotency_key do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
    |> then(fn <<a::binary-size(8), b::binary-size(4), c::binary-size(4), d::binary-size(4), e::binary-size(12)>> ->
      "#{a}-#{b}-#{c}-#{d}-#{e}"
    end)
  end

  defp encode(id), do: URI.encode_www_form(to_string(id))
end
