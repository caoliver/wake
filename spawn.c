// Simple interface to fork/exec.

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <errno.h>
#include <signal.h>

static int do_wait(lua_State *L)
{
  int status;
  pid_t process;
  process = wait(&status);
  if (process < 0)
    {
      lua_pushnil(L);
      return 1;
    }
  
  lua_pushinteger(L, (int)process);
  if (WIFSIGNALED(status))
    {
      lua_pushstring(L, "signal");
      lua_pushinteger(L, WTERMSIG(status));
    }
  else if (WIFEXITED(status))
    {
      lua_pushstring(L, "exit");
      lua_pushinteger(L, WEXITSTATUS(status));
    }
  else
    luaL_error(L, "Unexpected wait status: %d", status);
  return 3;
}

static const char **to_strings(lua_State *L, int offset, const char **array)
{
  int i, len;

  luaL_checktype(L, offset, LUA_TTABLE);
  len = lua_objlen(L, offset);
  array = realloc(array, sizeof(char *)*(len + 1));
  for (i = 1; i <= len; i++)
    {
      lua_rawgeti(L, offset, i);
      array[i - 1] = luaL_checkstring(L, -1);
      lua_pop(L, 1);
    }
  array[i - 1] = NULL;
  return array;
}

static int do_spawn(lua_State *L)
{
  const char *filename;
  static const char **argv, **envp;
  int new_env = 0, close_stdout = 0;
  int envarg = 3;
  pid_t process;

  filename = luaL_checkstring(L, 1);

  argv = to_strings(L, 2, argv);
  
  if (lua_isboolean(L, 3))
    {
      envarg = 4;
      close_stdout = lua_toboolean(L, 3);
    }

  if (!lua_isnone(L, envarg))
    {
      new_env = 1;
      envp = to_strings(L, envarg, envp);
    }

  switch (process = fork())
    {
    case -1:
      lua_pushnil(L);
      lua_pushinteger(L, errno);
      return 2;
    case 0:
      if (close_stdout)
	close(1);
      if (new_env)
	execvpe(filename, argv, envp);
      else
	execvp(filename, argv);
      exit(127);
    default:
      lua_pushinteger(L, (int)process);
      return 1;
    }
}


static int do_ignore_signals(lua_State *L)
{
  signal(SIGINT, SIG_IGN);
  signal(SIGQUIT, SIG_IGN);
  signal(SIGHUP, SIG_IGN);
  signal(SIGTSTP, SIG_IGN);
  return 0;
}

static int do_usleep(lua_State *L)
{
  usleep(luaL_checkint(L, 1));
  return 0;
}

static const luaL_Reg entry_pts[] = {
  {"ignore_signals", do_ignore_signals},
  {"usleep", do_usleep},
  {"spawn", do_spawn},
  {"wait", do_wait},
  {NULL, NULL}
};

int luaopen_spawn(lua_State *L)
{
  luaL_register(L, "spawn", entry_pts);
  return 1;
}
