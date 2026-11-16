defmodule Transmitly.Error do
  @moduledoc "Raised for a non-2xx response or a transport failure."

  defexception [:status, :code, :details, :payload, message: "Request failed"]

  @impl true
  def message(%__MODULE__{message: message, code: code}) when is_binary(code) and code != "" do
    "#{message} (#{code})"
  end

  def message(%__MODULE__{message: message}), do: message
end
