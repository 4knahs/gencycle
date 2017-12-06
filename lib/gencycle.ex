defmodule GenCycle do
  @moduledoc """

  # Under work 

  Documentation for Gencycle.
  
  The recipes model applies to any process that wants to execute independent tasks (in parallel) without becoming cluttered with task logic and having a state machine of executed tasks.

  Recipes are wrappers for simple actions to be performed in parallel.

  Each action runs in a supervised task and recipes can be pipelined via events.

  Processes like GenServer can import the `RecipeManager` to implement the recipes model.

  # Creating a Recipe

  Recipes lie in `lib/recipes`. To start create a new file there, e.g., `trace_recipe.ex`.

  First step is to tell it to follow the `GenCycle.RecipeBehavior`:

  ```
  defmodule GenCycle.Recipe.MyRecipe do
  @moduledoc false

  @behaviour GenCycle.RecipeBehavior
  
  end
  ```

  If you check the `RecipeBehavior` you will see it requires the following callback function:

  ```
  @callback start(state, event, message, return) :: :noevent | {:event, event, message} | {:event, event, message, return}
  ```

  So lets implement it:

  ```
  defmodule GenCycle.Recipe.MyRecipe do
  @moduledoc false

  require Logger

  @behaviour GenCycle.RecipeBehavior

  def start(_state, _event, _message, _return) do

    Logger.info "Invoked MyRecipe.start"

    :noevent #return this if there isnt another recipe waiting for this to conclude
  end
  end
  ```

  Note the four parameters received:
  * state - copy of the owner's state when this got invoked.
  * event - event that triggered the start method (e.g., `:event`)
  * message - event message that triggered the start method (e.g., `:done`)
  * return - if the triggering event passed a return value, then it is passed to start via the return parameter. Otherwise the parameter is set as :no_return. We will discuss this later.

  Now we have a recipe ready to be registered. 
  Recipes run whenever the event/message combination they are registered to is triggered.
  In this case we want them to run whenever an app is put foreground.

  Note that putting an app in the foreground is in itself a recipe.
  Unlike our `MyRecipe`, the `ForegroundRecipe` launches an event upon conclusion.
  To do so it returns `{:event, :foreground, :done}`.
  This is how recipes are pipelined between them, via returned events. 
  So lets register `MyRecipe` to be launched on this event in the `virtual_device.init\1` of `VirtualDevice`:

  ```
  state = state |> add_recipe(:foreground, :done, Patata.Recipe.MyRecipe)
  ```

  Done! Now whenever an app is put on foreground, `MyRecipe` executes.

  # Recipe Events

  With our recipe created and added via `add_recipe\3` (or `add_recipes\3`), if we want to launch it ourselves we can do it by launching the event they expect.
  For the previous example it could be achieved by:

  ```
  state |> launch_event({:foreground, :done})
  ```

  In the case of a timed event, one could do:

  ```
  state |> schedule_event(time_in_ms, {:foreground, :done})
  ```

  Occasionally one might want to cancel an event, to do so scheduled events can be named. E.g.:

  ```
  state |> schedule_event(time_in_ms, {:foreground, :done}, [name: foreground_event_name])
  ```

  And canceled using their event name:

  ```
  state |> cancel_event(foreground_event_name)
  ```

  # Pipelining recipes

  As we have seen, recipes can wait on one another by generating their own events.
  E.g., by returning:

  ```
  {:event, :your-event, :your-message}
  ```

  and registering the recipe on that event and message/status:

  ```
  state |> add_recipe(:your-event, :your-message, Patata.Recipe.YourRecipe)
  ```

  Additionally state can also be passed with the events by returning four fields instead:

  ```
  {:event, :your-event, :your-message, :your-state}
  ```

  Two important notes:
  * Both the event and message need to be matchable, i.e., something constant, either an atom or a string.
  * Recipes' start method is executed in its own task and its state and return parameters are copies and therefore any change to them is not propagated.
  * Do not generate atoms automatically since these are not garbage collected. Try to reuse atoms.

  # Waiting for recipes

  In many cases you might want to wait for a few recipes to conclude before launching a new event/recipe.
  To do this we have introduced `gather_events\4` :

  ```
  data_events = [ # List of events to be matched
                  {:event_one, :message_one},
                  {:event_two, :message_two}  
               ]

  state
    |> gather_events(
        data_events,                    # List of events to be matched
        {:event_start, :message_start}, # Starts matching events from this event
        {:event_out, :message_out})     # On matching all events launches this event
  ```

  This function waits on the completion of group of recipes by listening to their returning events (as specified by `data_events`). 
  It only considering events since the occurrence of a starting event (`event_start`) to support repeating gathers over time.
  On successfully matching all the events it launches a completion event that can be used to start other recipes.

  Internally, the `gather_events\4` function registers a listener on all the awaited events (`data_events`). Whenever one of these events occurs, a specialized recipe (`GatherRecipe`) checks for the occurrence of the starting event (`event_start`) in the event history and tries to match the awaited events in the subsequent events in history.

  Important note: 
  *  If your gather depends on recipes that might fail it is up to you to make sure that either the matching events occur nonetheless, otherwise the gather will never output its event.
  
  """

  require Logger

  alias Patata.Recipe.GatherRecipe
  alias Patata.Recipe.GatherAllRecipe

  @events_to_show 5 # Will print the last 5 events to console


  @doc """
  Method to be invoked with GenServer state in init\1, it adds the required state to run GenCycle.

  ## Examples

      def init(:ok) do
        {:ok, init_recipes(%{})}
      end

  """
  @spec init_recipes(map, pid)::map
  def init_recipes(state, pid) do
    state
    |> Map.put(:owner_pid, pid)
    |> Map.put(:recipes, %{})         # This is where recipes are stored, dont edit
    |> Map.put(:future_events, [])    # This keeps the scheduled events
    |> Map.put(:running_recipes, [])  # This keeps the running recipes
    |> Map.put(:history, [])          # This keeps an history of the latest events
  end

  @doc """
  Launches an {event, status} that can trigger an existing recipe.
  If your recipe does not require any state invoke launch_event\2,
  otherwise launch_event\3 can be called, where the third argument
  is the state to be passed to the recipe.

  ## Examples

  def handle_cast({:launch_recipe}, state) do
    {:noreply, launch_event(state, {:new_event, :new_status})
  end

  """
  def launch_event(state, {event, status}, return \\ :no_return) do
    notify_owner(state, event, status, return)
    state
  end

  @doc """
  Returns true if an event (e.g., {:event,:status}) occurred before.

  ## Examples

  iex> event_in_history?(state, {:new_event, :new_status})
  false

  """
  def event_in_history?(state, event) do
    Enum.reduce(state.history, false, &(&2 || &1 == event))
  end

  defp print_events(state) do

    Logger.info "GenCycle: GenCycle.print_events"

    Enum.each(state.future_events, fn {atom_name, timer_ref, _} ->
      Logger.info "--Event #{atom_name}:#{inspect timer_ref} in #{Process.read_timer(timer_ref)}"
    end)

    state
  end

  # Requires state persistency

  def schedule_event(state, period, {event, status}, options \\ []) do

    defaults = [return: :no_return, name: :no_name]

    options = Keyword.merge(defaults, options) |> Enum.into(%{})

    %{name: name, return: return} = options

    Logger.info "GenCycle: GenCycle.schedule_event: Scheduling #{name} event #{event}:#{status} in #{period/1000}s"

    #TODO: Should check if successful here?
    timer_ref = Process.send_after(state.owner_pid, {:event, event, status, return}, period)

    Map.put(state, :future_events,
      [ {name, timer_ref, DateTime.to_unix(DateTime.utc_now()) + period } | state.future_events ])
    |> print_events()

  end

  def cancel_event(state, name) do

    Logger.info "GenCycle: Cancelling event : #{name}"

    timers = state.future_events
             |> Enum.filter(fn {n, _, _} -> n == name end)

    Enum.each(timers, fn {_, timer, _} ->
      case Process.cancel_timer(timer) do
        false ->
          Logger.error "GenCycle: Failed to cancel #{name} timer"
        _ ->
          Logger.info "GenCycle: Canceled #{name} timer"
      end
    end)

    Map.put(state, :future_events, state.future_events -- timers)

  end

  def cancel_all_events(state) do

    Logger.info "GenCycle: Cancelling all events"

    Enum.each(state.future_events, fn {_, timer, _} -> Process.cancel_timer(timer) end)

    Map.put(state, :future_events, [])
  end

  def gather_events(state, events, event_start, event_out) do
    Logger.info "GenCycle: GenCycle.gather_events: #{inspect events}"

    # Adds a special recipe that goes through the VD history to match events
    # This specific action is matched differently on on_event
    # The recipe runs whenever one of the events occurs, goes through the history and decides
    # if it should or shouldnt launch the event_out
    Enum.reduce(events, state,
      fn ev, acc ->
        add_recipe(acc, ev, {event_start, event_out, events, GatherRecipe})
      end
    ) # Returns the state as acc
  end

  # Be sure there are no periodic events going on when this runs!
  # Only run one of these at any point in time!
  def gather_all_events(state, event_in, event_out) do
    Logger.info "GenCycle: GenCycle.gather_all_events: Waiting on all event termination"
    add_recipe(state, event_in, {event_out, GatherAllRecipe})
  end

  def drop_events(state, {event, status}) do
    Map.put(state, :recipes, Map.delete(state.recipes, event))
  end

  def add_recipes(state, {event, status}, actions) do
    Logger.info "GenCycle: GenCycle.add_recipes: Adding recipe  #{event}:#{status}:#{inspect actions}"

    Enum.reduce(actions, state,
      fn action, acc ->
        add_recipe(acc, {event, status}, action)
      end
    )
  end

  # Requires state persistency
  def add_recipe(state, {event, status}, action) do

    Logger.info "GenCycle: GenCycle.add_recipe: Adding recipe #{event}:#{status}:#{inspect action}"

    recipes = case state.recipes[event] do
      nil -> Map.put(state.recipes, event, %{})
      _ -> state.recipes
    end

    recipes_event = case recipes[event][status] do
      nil -> Map.put(recipes[event], status, [])
      _  -> recipes[event]
    end

    recipes_event = Map.put(recipes_event, status, recipes_event[status] ++ [action])

    recipes = Map.put(state.recipes, event, recipes_event)

    # Logger.info "GenCycle.add_recipe: Added recipe."

    Map.put(state, :recipes, recipes)
  end

  def on_event(state, {event, status}, return) do

    Logger.info "GenCycle: GenCycle.on_event: #{event}:#{inspect status}"

    state = state
            |> add_event_to_history(event, status) # Populates the event history
            |> filter_dead_recipes()               # Filters dead recipes
            |> filter_expired_events()             # Filters expired scheduled events

    cond do
      state.recipes[event] == nil ->
        Logger.info "GenCycle: GenCycle.on_event: No events for #{event}"
        state # no listeners on this event
      state.recipes[event][status] == nil ->
        Logger.info "GenCycle: GenCycle.on_event: No events for combination #{event}:#{inspect status}"
        state # no listeners on this status
      true -> # found listeners on the event and status
        Logger.info "GenCycle: GenCycle.on_event: Found actions for #{event}:#{inspect status}"
        Enum.reduce(state.recipes[event][status], state, fn action, acc ->
          case action do
            # This is a special case, i.e. a gather event!
            {in_event, out_event, events, action} ->
              launch_action(acc, action, event, status,
                [in_event: in_event, out: out_event, events: events])

            {out_event, action}   ->
              launch_action(acc, action, event, status, out_event)

            # This is a normal recipe
            _ -> launch_action(acc, action, event, status, return)
          end
        end) # launch_action returns state and adds the recipe pid
    end

  end

  defp add_event_to_history(state, event, message) do

    # TODO: adding to the end is expensive, and we use it reverted in GatherRecipe
    history = state.history ++ [{event, message}]

    len = length(history)

    history_to_show = cond do
      len > 0 ->
        to_show = cond do
          len >= @events_to_show -> @events_to_show
          true -> len
        end

        history_to_show = Enum.slice(history,(len-to_show)..(len-1))
      true ->
        history
    end

    #Logger.info "History (last #{@events_to_show} events)---------"
    #Enum.each(history_to_show, fn x -> Logger.info "#{inspect x}" end)
    #Logger.info "-----------------------------------"

    Map.put(state, :history, history)
  end

  defp filter_dead_recipes(state) do

    running = Enum.filter(state.running_recipes, fn pid -> Process.alive?(pid) end)

    Map.put(state, :running_recipes, running)
  end

  defp filter_expired_events(state) do

    time = DateTime.to_unix(DateTime.utc_now())
    events = Enum.filter(state.future_events,
      fn {_, _, unix_time} -> ( time < unix_time)  end)

    Map.put(state, :future_events, events)
  end

  def log_recipes(recipes) do
    Enum.each(recipes, fn {ev, v} ->
      Logger.info "Event #{ev} -------"
      Enum.each(v, fn {stat, act} ->
        Logger.info "  -- Status #{stat} with actions: #{inspect act}"
      end)
    end)
  end

  defp launch_action(state, action, event, status, return) do
    {:ok, pid} = Task.Supervisor.start_child(Patata.TaskSupervisor, fn ->
      Logger.info "GenCycle: GenCycle.launch_action: Launched task for recipe: #{inspect action}"
      case action.start(state, event, status, return) do
        {:event, event, message} ->
          notify_owner(state, event, message, :no_return)
        {:event, event, message, return} ->
          notify_owner(state, event, message, return)
        :no_event ->
          Logger.info "GenCycle: GenCycle.launch_action: Ommiting event for recipe #{inspect action}"
      end
    end)

    Map.put(state, :running_recipes, [ pid | state.running_recipes])
  end

  defp notify_owner(state, event, message, return) do
    GenServer.cast(state.owner_pid, {:event, event, message, return})
  end

end
