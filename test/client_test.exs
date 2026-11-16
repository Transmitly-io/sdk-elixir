defmodule Transmitly.ClientTest do
  use ExUnit.Case, async: false

  alias Transmitly.Client

  test "verifies webhook signatures" do
    secret = "whsec_test"
    body = ~s({"type":"email.delivered_to_mx"})
    timestamp = System.system_time(:second)
    signature = :crypto.mac(:hmac, :sha256, secret, "#{timestamp}.#{body}") |> Base.encode16(case: :lower)
    header = "t=#{timestamp},v1=#{signature}"

    assert Client.verify_webhook(body, header, secret)
    refute Client.verify_webhook(body, header, "wrong")
    refute Client.verify_webhook(body, "t=#{timestamp - 400},v1=#{signature}", secret)
    refute Client.verify_webhook(body, "garbage", secret)
  end

  test "validates before the network" do
    tx = Client.new("txk_test")

    assert_raise ArgumentError, fn ->
      Client.send_email(tx, %{"from" => "a@acme.com", "to" => [], "subject" => "s", "text" => "t"})
    end

    assert_raise ArgumentError, fn ->
      Client.send_email(tx, %{"from" => "a@acme.com", "to" => ["b@example.net"], "subject" => "s"})
    end

    assert_raise ArgumentError, fn -> Client.new("") end
  end

  test "sends the payload with an idempotency key" do
    {base_url, task} =
      one_shot_server(202, ~s({"id":"msg_123","status":"accepted","recipients":1}))

    tx = Client.new("txk_test", base_url)

    accepted =
      Client.send_email(
        tx,
        %{
          "from" => "Notify <notify@acme.com>",
          "to" => ["ada@example.net"],
          "subject" => "Welcome",
          "html" => "<p>Hi</p>",
          "tags" => %{"flow" => "onboarding"}
        },
        idempotency_key: "welcome-1"
      )

    assert accepted["id"] == "msg_123"

    {request_line, headers, body} = Task.await(task)
    assert request_line == "POST /v1/emails HTTP/1.1"
    assert headers["authorization"] == "Bearer txk_test"
    assert headers["idempotency-key"] == "welcome-1"
    payload = Jason.decode!(body)
    assert payload["from"] == "Notify <notify@acme.com>"
    assert payload["to"] == ["ada@example.net"]
    assert payload["tags"] == %{"flow" => "onboarding"}
  end

  test "maps API errors" do
    {base_url, task} =
      one_shot_server(409, ~s({"error":{"code":"idempotency_conflict","message":"Already used"}}))

    tx = Client.new("txk_test", base_url)

    error =
      assert_raise Transmitly.Error, fn ->
        Client.send_email(tx, %{
          "from" => "a@acme.com",
          "to" => ["b@example.net"],
          "subject" => "s",
          "text" => "t"
        })
      end

    assert error.status == 409
    assert error.code == "idempotency_conflict"
    assert error.message == "Already used"
    Task.await(task)
  end

  test "live smoke when configured" do
    case System.get_env("TRANSMITLY_API_KEY") do
      nil ->
        :ok

      api_key ->
        tx = Client.new(api_key, System.get_env("TRANSMITLY_BASE_URL") || "https://transmitly.io")

        accepted =
          Client.send_email(tx, %{
            "from" => "Notify <notify@transmitly.io>",
            "to" => ["sdk-elixir@transmitly.test"],
            "subject" => "Elixir SDK smoke",
            "text" => "hello",
            "test_mode" => true
          })

        assert accepted["status"] == "accepted"
        assert accepted["test_mode"] == true
    end
  end

  defp one_shot_server(status, response) do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, packet: :raw, reuseaddr: true])
    {:ok, port} = :inet.port(listen)

    task =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listen)

        {head, body} = read_request(socket, "")

        :gen_tcp.send(
          socket,
          "HTTP/1.1 #{status} Test\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(response)}\r\nConnection: close\r\n\r\n#{response}"
        )

        :gen_tcp.close(socket)
        :gen_tcp.close(listen)
        parse_request(head, body)
      end)

    {"http://127.0.0.1:#{port}", task}
  end

  defp read_request(socket, acc) do
    case String.split(acc, "\r\n\r\n", parts: 2) do
      [head, rest] ->
        length =
          head
          |> String.split("\r\n")
          |> Enum.find_value(0, fn line ->
            case String.split(line, ":", parts: 2) do
              [key, value] -> if String.downcase(key) == "content-length", do: String.to_integer(String.trim(value))
              _ -> nil
            end
          end)

        {head, read_body(socket, rest, length)}

      _ ->
        {:ok, chunk} = :gen_tcp.recv(socket, 0, 2000)
        read_request(socket, acc <> chunk)
    end
  end

  defp read_body(_socket, body, length) when byte_size(body) >= length, do: body

  defp read_body(socket, body, length) do
    {:ok, chunk} = :gen_tcp.recv(socket, 0, 2000)
    read_body(socket, body <> chunk, length)
  end

  defp parse_request(head, body) do
    [request_line | lines] = String.split(head, "\r\n")

    headers =
      lines
      |> Enum.reduce(%{}, fn line, acc ->
        case String.split(line, ":", parts: 2) do
          [key, value] -> Map.put(acc, String.downcase(key), String.trim(value))
          _ -> acc
        end
      end)

    {request_line, headers, body}
  end
end
