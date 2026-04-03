Um die Kali Shell z.b. auf Linux Mint zu installieren


ZSH installieren: 

```
sudo apt update && sudo apt install zsh
```

Optional Verzeichnis prüfen:(normalerweise /usr/bin/zsh). 
```
which zsh
```


Standard-Shell ändern: 

```
chsh -s $(which zsh).
```



Packets

```
sudo apt install zsh-syntax-highlighting zsh-autosuggestions
```

Fonts

```
sudo apt install fonts-powerline
```

Die Design Datei (.zshrc) selbst laden
```
wget -O ~/.zshrc https://gitlab.com/kalilinux/packages/kali-defaults/-/raw/kali/master/etc/skel/.zshrc
```

