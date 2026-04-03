<img width="843" height="595" alt="image" src="https://github.com/user-attachments/assets/b12487d3-b01d-4bcf-a6d8-c7860359ec01" />


Um die Kali Shell z.b. auf Linux Mint zu installieren


ZSH installieren: 

```
sudo apt update && sudo apt install zsh
```


Optional Verzeichnis prüfen: (normalerweise /usr/bin/zsh). 
```
which zsh
```


Standard-Shell ändern: 

```
chsh -s $(which zsh).
```


Packete installieren

```
sudo apt install zsh-syntax-highlighting zsh-autosuggestions
```

Fonts installieren

```
sudo apt install fonts-powerline
```

Die Design Datei (.zshrc) selbst laden (ins eigene home Verzeichnis)

```
cd ~
wget -O ~/.zshrc https://gitlab.com/kalilinux/packages/kali-defaults/-/raw/kali/master/etc/skel/.zshrc
```

Neu laden

```
source ~/.zshrc
```

Oder Shell schließen und neu öffnen
