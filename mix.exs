defmodule Transmitly.MixProject do
  use Mix.Project

  @version "1.0.1"

  def project do
    [
      app: :transmitly,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Elixir client for the Transmitly email API",
      package: package(),
      source_url: "https://github.com/Transmitly-io/sdk-elixir",
      homepage_url: "https://transmitly.io/docs/sdks"
    ]
  end

  def application do
    [extra_applications: [:logger, :inets, :ssl, :crypto]]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/Transmitly-io/sdk-elixir"},
      files: ~w(lib mix.exs README.md LICENSE)
    ]
  end
end
