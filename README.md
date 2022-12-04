# SandboxRegistry
[![Dialyzer](https://github.com/MikaAK/sandbox_registry/actions/workflows/dialyzer.yml/badge.svg)](https://github.com/MikaAK/sandbox_registry/actions/workflows/dialyzer.yml)
[![Credo](https://github.com/MikaAK/sandbox_registry/actions/workflows/credo.yml/badge.svg)](https://github.com/MikaAK/sandbox_registry/actions/workflows/credo.yml)

We can use the sandbox registry to help create sandboxes for testing

Sandboxes help us test by allow us to specify a mock that will be utilzed only for the specific test, allowing
us to modify the return value of a specific function only in test.

We can utilize this pattern by building around an adapter pattern, and using the sandbox in dev mode. Other ways to build this pattern
include using a flag like `sandbox?` to enable sandbox mode and swap out calls to a sanbox

### Example Sandbox
```elixir
defmodule HTTPSandbox do
  @registry :http_sandbox
  @keys :unique

  def start_link do
    Registry.start_link(keys: @keys, name: @registry)
  end

  def set_get_responses(tuples) do
    tuples
    |> Map.new(fn {url, func} -> {{:get, url}, func} end)
    |> then(&SandboxRegistry.register(@registry, @state, &1, @keys))
    |> case do
      :ok -> :ok
      {:error, :registry_not_started} -> raise_not_started!()
    end

    # Random sleep is needed to allow registry time to insert
    Process.sleep(50)
  end


  def get_response(url, headers, options) do
    func = find!(:get, url)

    func.(url, headers, options)
  end

  def find!(method, url) do
    case SandboxRegistry.lookup(@registry, @state) do
      {:ok, funcs} ->
        find_response!(funcs, method, url)

      {:error, :pid_not_registered} ->
        raise """
        No functions registered for #{inspect(self())}
        Action: #{inspect(action)}
        URL: #{inspect(url)}

        ======= Use: =======
        #{format_example(action, url)}
        === in your test ===
        """

      {:error, :registry_not_started} ->
        raise """
        Registry not started for #{inspect(__MODULE__)}.
        Please add the line:

        #{inspect(__MODULE__)}.start_link()

        to test_helper.exs for the current app.
        """
    end
  end
end
```

Now we can use this in an HTTP module only in test by doing
```elixir
defmodule HTTP do
  @defaults_opts [
    sandbox?: Mix.env() === :test
  ]

  def get(url, header, opts) do
    opts = Keyword.merge(@defaults_opts, opts)

    if opts[:sandbox?] do
      HTTPSandbox.get_response(url, headers, opts)
    else
      make_get_request()
    end
  end
end
```

Now in test we have the ability to mock out our get requests per test
```elixir
describe "some get request" do
  test "test get /url" do
    HTTPSandbox.set_get_responses([{
      "myurl.com",
      fn _url, _headers, _opts -> {:ok, :whatever} end
    }])

    assert {:ok, :whatever} === HTTP.get("myurl.com", [], [])
  end
end
```


## Installation

[Available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `sandbox_registry` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:sandbox_registry, "~> 0.1.0"}
  ]
end
```

The docs can be found at <https://hexdocs.pm/sandbox_registry>.

