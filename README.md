# ВШЭ. Анализ уязвимостей в Web3

> - Домашнее задание №2
> - Студент: Крамаренко Михаил

## Инструкция запуска

1. Скачать репозиторий:
   ```
   git clone --recurse-submodules https://github.com/Mi-Kram/HseWeb3-hw2.git
   cd HseWeb3-hw2
   git submodule update --init --recursive
   ```

2. Node-зависимости:
   ```
   npm.cmd ci
   ```

3. На Windows задайть путь к Git Bash:
   ```
   $env:OPENZEPPELIN_BASH_PATH = 'C:\Program Files\Git\bin\bash.exe'
   ```

4. Запустить сборку и тесты:
   ```
   forge clean
   forge build
   forge test
   ```
