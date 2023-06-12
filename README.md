# SandboxRegistry
[![Dialyzer](https://github.com/alanvardy/sandbox_registry/actions/workflows/dialyzer.yml/badge.svg)](https://github.com/alanvardy/sandbox_registry/actions/workflows/dialyzer.yml)
[![Credo](https://github.com/alanvardy/sandbox_registry/actions/workflows/credo.yml/badge.svg)](https://github.com/alanvardy/sandbox_registry/actions/workflows/credo.yml)
[![Build Status](https://github.com/alanvardy/sandbox_registry/actions/workflows/test.yml/badge.svg)](https://github.com/alanvardy/sandbox_registry/actions/workflows/test.yml)
[![Build Status](https://github.com/alanvardy/sandbox_registry/actions/workflows/coverage.yml/badge.svg)](https://github.com/alanvardy/sandbox_registry/actions/workflows/coverage.yml)
[![Build Status](https://github.com/alanvardy/sandbox_registry/actions/workflows/doctor.yml/badge.svg)](https://github.com/alanvardy/sandbox_registry/actions/workflows/doctor.yml)


We can use the sandbox registry to help create sandboxes for testing

Sandboxes help us test by allow us to specify a mock that will be utilized only for the specific test, allowing
us to modify the return value of a specific function only in test.

We can utilize this pattern by building around an adapter pattern, and using the sandbox in dev mode. Other ways to build this pattern
include using a flag like `sandbox?` to enable sandbox mode and swap out calls to a sandbox

### Example Sandbox
```elixir
defmodule HTTPSandbox do
 @moduledoc """
  For mocking out HTTP GET requests in test.

  Stores a map of functions in a Registry under the PID of the test case when
  `set_get_responses/1` is called.

  """
  @registry :http_sandbox
  @keys :unique
  # state is a sub-key to allow multiple contexts to use the same registry
  @state "http"
  @sleep 10  

  def start_link do
    Registry.start_link(keys: @keys, name: @registry)
  end


  @doc """
  Can be called in HTTP client module in test environment instead of get request to external API
  """
  def get_response(url, headers, options) do
    func = find!(:get, url)

    case :erlang.fun_info(func)[:arity] do
      0 -> func.()
      3 -> func.(url, headers, options)
    end
  end


  @doc """
  Set sandbox responses in test. Call this function in your setup block with a list of tuples.

  The tuples have two elements:
  - The first element is either a string url or a regex that needs to match on the url
  - The second element is a 0 or 3 arity anonymous function. The arguments for the 3 arity
  are url, headers, options.


  
  `HTTPSandbox.set_get_responses([{"http://google.com/", fn ->
    {:ok, {"I am a response", %{status: 200}}}
  end}])`

  the url headers and opts can be pattern matched here to assert the correct request was sent.
  `HTTPSandbox.set_get_responses([
    {"http://google.com/", fn url, headers, opts ->
      {:ok, {"I am a response", %{status: 200}}}
    end}])` 

  """

  def set_get_responses(tuples) do
    tuples
    |> Map.new(fn {url, func} -> {{:get, url}, func} end)
    |> then(&SandboxRegistry.register(@registry, @state, &1, @keys))
    |> case do
      :ok -> :ok
      {:error, :registry_not_started} -> raise_not_started!()
    end

    # Random sleep is needed to allow registry time to insert
    Process.sleep(@sleep)
  end
  
   @doc """
  Finds out whether its PID or one of its ancestor's PIDs have been registered
  Returns response function or raises an error for developer
  """
  def find!(action, url) do
    case SandboxRegistry.lookup(@registry, @state) do
      {:ok, funcs} ->
        find_response!(funcs, action, url)

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

  defp find_response!(funcs, action, url) do
    key = {action, url}

    with funcs when is_map(funcs) <- Map.get(funcs, key, funcs),
         regexes <- Enum.filter(funcs, fn {{_, k}, _v} -> Regex.regex?(k) end),
         {_regex, func} when is_function(func) <-
           Enum.find(regexes, funcs, fn {{_, k}, _v} -> Regex.match?(k, url) end) do
      func
    else
      func when is_function(func) ->
        func

      functions when is_map(functions) ->
        functions_text =
          Enum.map_join(functions, "\n", fn {k, v} -> "#{inspect(k)}    =>    #{inspect(v)}" end)

        raise """
        Response not found in registry for {action, url} in #{inspect(self())}
        Found in registry:
        #{functions_text}

        ======== Add this: ========
        #{format_example(action, url)}
        === in your test setup ====
        """

      other ->
        raise """
        Unrecognized input for {action, url} in #{inspect(self())}

        Did you use
        fn -> function() end
        in your set_get_responses/1 ?

        Found:
        #{inspect(other)}

        ======= Use: =======
        #{format_example(action, url)}
        === in your test ===
        """
    end
  end

  defp format_example(action, url) do
    """
    setup do
      HTTPSandbox.set_#{action}_responses([
        {#{inspect(url)}, fn _url, _headers, _options -> _response end},
        # or
        {#{inspect(url)}, fn -> _response end}
        # or
        {~r|http://na1|, fn -> _response end}
      ])
    end
    """
  end

  defp raise_not_started! do
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

For our tests, we need to add `HTTPSandbox.start_link()` to our `test_helpers.exs` file. Now we have the ability to mock out our get requests per test

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
    {:sandbox_registry, "~> 0.1.1"}
  ]
end
```

The docs can be found at <https://hexdocs.pm/sandbox_registry>.

