# Role: Student ministry (NextGen) presentation computer.
# "SA cg-1 only needs propresenter."
{ lib, ... }:

{
  production.macApps.apps = [
    "propresenter"
  ];
}
