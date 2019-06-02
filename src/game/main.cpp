#include "Player.h"

#include <engine/Application.h>

#include <sr1/memory>

#include <iostream>

int main()
{
  Player p;
  std::sr1::shared_ptr<Player> pp;

  pp = std::sr1::make_shared<Player>();

  std::cout << "Hello World" << std::endl;

  return 0;
}
