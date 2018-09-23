defmodule Vorta.MixProject do
  use Mix.Project

  def project do
    [
      app: :vorta,
      version: "0.1.0",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Vorta.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:dialyxir, "~> 0.5", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.19", only: [:dev], runtime: false},
      {:entangle, git: "https://github.com/nanaki04/entangle_ex.git"}
    ]
  end
end
