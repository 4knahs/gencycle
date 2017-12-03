defmodule Gencycle.Mixfile do
  use Mix.Project

  def project do
    [
      app: :gencycle,
      name: "GenCycle",
      source_url: "https://github.com/4knahs/gencycle",
      description: "An event-driven task manager to design GenServer lifecycles",
      package: package(),
      version: "0.1.0",
      elixir: "~> 1.5",
      start_permanent: Mix.env == :prod,
      deps: deps()
    ]
  end

  defp package do
    [
      maintainers: ["4knahs"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/4knahs/gencycle"}
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.16", only: :dev, runtime: false}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"},
    ]
  end
end
