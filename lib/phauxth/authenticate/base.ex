defmodule Phauxth.Authenticate.Base do
  @moduledoc """
  Base module for authentication.

  This is used by Phauxth.Authenticate and Phauxth.Remember.
  It can also be used to produce a custom authentication module,
  as outlined below.

  ## Custom authentication modules

  The next sections give examples of extending this module to create
  custom authentication modules.

  ### Graphql authentication

  The following module is another example of how this Base module can
  be extended, this time to provide authentication for absinthe-elixir:

      defmodule AbsintheAuthenticate do
  use Phauxth.Authenticate.Base, :token # add docs about adding :token to use

        def set_user(user, conn) do
          put_private(conn, :absinthe, %{token: %{current_user: user}})
        end
      end

  And in the `router.ex` file, call this plug in the pipeline you
  want to authenticate.

      pipeline :api do
        plug :accepts, ["json"]
        plug AbsintheAuthenticate
      end

  ### Authentication for use with Phoenix channels

  In this example, after adding the user struct to the current_user value,
  a token is added (for use with Phoenix channels).

      defmodule MyAppWeb.Authenticate do
        use Phauxth.Authenticate.Base

        def set_user(nil, conn), do: assign(conn, :current_user, nil)
        def set_user(user, conn) do
          token = Phauxth.Token.sign(conn, %{"user_id" => user.email})
          assign(conn, :current_user, user)
          |> assign(:user_token, token)
        end
      end

  MyAppWeb.Authenticate is called in the same way as Phauxth.Authenticate.
  You can then use Phauxth.Token.verify, in the `user_socket.ex` file, to
  verify the token.
  """

  @doc """
  Get the user based on the session id or token id.

  This function also calls the database to get user information.
  """
  @callback get_user(conn :: Plug.Conn.t(), opts :: tuple) :: map | {:error, String.t()} | nil

  @doc """
  Log the result of the authentication and return the user struct or nil.
  """
  @callback report(result :: tuple, metadata :: keyword) :: map | nil

  @doc """
  Set the `current_user` variable.
  """
  @callback set_user(user :: map | nil, conn :: Plug.Conn.t()) :: Plug.Conn.t()

  @doc false
  defmacro __using__(options) do
    user_data_mod = Keyword.get(options, :user_data, Phauxth.Authenticate.Session)

    quote do
      import Plug.Conn
      import unquote(user_data_mod)
      alias Phauxth.{Config, Log, Utils}

      @behaviour Plug
      @behaviour Phauxth.Authenticate.Base

      @impl Plug
      def init(opts) do
        {
          {
            Keyword.get(opts, :max_age, 4 * 60 * 60),
            Keyword.get(opts, :user_context, Utils.default_user_context()),
            opts
          },
          Keyword.get(opts, :log_meta, [])
        }
      end

      @impl Plug
      def call(conn, {opts, log_meta}) do
        get_user(conn, opts) |> report(log_meta) |> set_user(conn)
      end

      @impl Phauxth.Authenticate.Base
      def get_user(conn, opts) do
        get_user_data(conn, opts)
      end

      @impl Phauxth.Authenticate.Base
      def report(%{} = user, meta) do
        Log.info(%Log{user: user.id, message: "user authenticated", meta: meta})
        Map.drop(user, Config.drop_user_keys())
      end

      def report({:error, message}, meta) do
        Log.info(%Log{message: message, meta: meta}) && nil
      end

      def report(nil, meta) do
        Log.info(%Log{message: "anonymous user", meta: meta}) && nil
      end

      @impl Phauxth.Authenticate.Base
      def set_user(user, conn) do
        assign(conn, :current_user, user)
      end

      defoverridable Plug
      defoverridable Phauxth.Authenticate.Base
    end
  end
end
