for notifier <- [Oban.Notifiers.Isolated, Oban.Notifiers.PG, Oban.Notifiers.Postgres] do
  defmodule Module.concat(notifier, Test) do
    use Oban.Case, async: notifier != Oban.Notifiers.Postgres

    alias Ecto.Adapters.SQL.Sandbox
    alias Oban.Notifier

    @notifier notifier

    describe "with #{inspect(notifier)}" do
      test "broadcasting notifications to subscribers" do
        unboxed_run(fn ->
          name = start_supervised_oban!(notifier: @notifier)

          :ok = Notifier.listen(name, :signal)
          :ok = Notifier.notify(name, :signal, %{incoming: "message"})

          assert_receive {:notification, :signal, %{"incoming" => "message"}}
        end)
      end

      test "notifying with complex types" do
        unboxed_run(fn ->
          name = start_supervised_oban!(notifier: @notifier)

          Notifier.listen(name, [:insert, :gossip, :signal])

          Notifier.notify(name, :signal, %{
            date: ~D[2021-08-09],
            keyword: [a: 1, b: 1],
            map: %{tuple: {1, :second}},
            tuple: {1, :second}
          })

          assert_receive {:notification, :signal, notice}
          assert %{"date" => "2021-08-09", "keyword" => [["a", 1], ["b", 1]]} = notice
          assert %{"map" => %{"tuple" => [1, "second"]}, "tuple" => [1, "second"]} = notice
        end)
      end

      test "broadcasting on select channels" do
        unboxed_run(fn ->
          name = start_supervised_oban!(notifier: @notifier)

          :ok = Notifier.listen(name, [:signal, :gossip])
          :ok = Notifier.unlisten(name, [:gossip])

          :ok = Notifier.notify(name, :gossip, %{foo: "bar"})
          :ok = Notifier.notify(name, :signal, %{baz: "bat"})

          assert_receive {:notification, :signal, _}
          refute_received {:notification, :gossip, _}
        end)
      end

      test "ignoring messages scoped to other instances" do
        unboxed_run(fn ->
          name = start_supervised_oban!(notifier: @notifier)

          :ok = Notifier.listen(name, [:gossip, :signal])

          ident =
            name
            |> Oban.config()
            |> Config.to_ident()

          :ok = Notifier.notify(name, :gossip, %{foo: "bar", ident: ident})
          :ok = Notifier.notify(name, :signal, %{foo: "baz", ident: "bogus.ident"})

          assert_receive {:notification, :gossip, _}
          refute_received {:notification, :signal, _}
        end)
      end
    end

    defp unboxed_run(fun) do
      if @notifier == Oban.Notifiers.Postgres do
        Sandbox.unboxed_run(Repo, fun)
      else
        fun.()
      end
    end
  end
end
