#!/bin/bash

# Check for package manager (apt)
if [ ! -x "$(command -v apt-cache)" ]; then
  yad --error --title="Error" --text="Unsupported package manager. This script requires apt-cache."
  exit 1
fi

# Main menu function
main_menu() {
  user_choice=$(yad --list --radiolist \
    --title="Package Management" \
    --text="Select an action:" \
    --column="Select" --column="Action" \
    TRUE "Search Packages" FALSE "Install Package" FALSE "Remove Package" FALSE "List Installed Packages" FALSE "Exit" \
    --width=300 --height=300 --center)

    case $user_choice in
    *"Search Packages"*)
      search_packages
      ;;
    *"Install Package"*)
      install_package
      ;;
    *"Remove Package"*)
      remove_package
      ;;
    *"List Installed Packages"*)
      list_installed_packages
      ;;
    *"Exit"*)
      exit 0
      ;;
  esac
}

# Search for packages
search_packages() {
  search_term=$(yad --entry --title="Search Packages" --text="Search Package name on Internet\nEnter search term:" --width=300 --height=100 --center)
  if [[ -n "$search_term" ]]; then
    package_list=$(apt-cache search "$search_term" 2>/dev/null)
    if [[ $? -eq 0 && -n "$package_list" ]]; then
      yad --title="Search Results" --text="$package_list" --width=600 --height=400 --wrap --center
    else
      yad --info --title="Search Packages" --text="No packages found." --center
    fi
  fi
  main_menu
}


# Install package
install_package() {
  result=$(yad --form --title="Install Package" \
    --text="\n<span size='larger'><b>Choose an option:</b></span>\n\ 
      1. Browse .deb Packages\n \
      2. Browse Snapcraft\n \
      3. Browse Flathub\n\n \
    or enter the package name to install directly:" \
    --field="Browse Flathub:FBTN" "xdg-open https://flathub.org/" \
    --field="Browse Snapcraft:FBTN" "xdg-open https://snapcraft.io/store" \
    --field="Browse .deb Packages:FBTN" "xdg-open https://packages.ubuntu.com/" \
    --field="Package Name" "" \
    --center --width=400 --button="gtk-ok:0" --button="gtk-cancel:1 \
    --html")

  # Extract the package name
  package_name=$(echo "$result" | awk -F '|' '{print $4}')

  if [[ -n "$package_name" ]]; then
    if [[ "$result" =~ "Browse .deb Packages" ]]; then
      xdg-open "https://packages.ubuntu.com/"
      install_package
    elif [[ "$result" =~ "Browse Snapcraft" ]]; then
      xdg-open "https://snapcraft.io/store"
      install_package
    elif [[ "$result" =~ "Browse Flathub" ]]; then
      xdg-open "https://flathub.org/"
      install_package
    else
      # Use pkexec for apt install
      (
        # Capture the output of apt install command
        output=$(pkexec bash -c "apt install -y $package_name 2>&1")
        install_status=$?

        if [[ $install_status -eq 0 ]]; then
          yad --info --title="Package Management" --text="Package '$package_name' installed successfully.\n\n$output" --center
        else
          yad --error --title="Error" --text="Failed to install package '$package_name'.\n\n$output" --center
        fi
      ) &

      # Wait for the background process to finish
      wait

      # Show the main menu after the user closes the info or error dialog
      main_menu
    fi
  else
    # If user cancels the input dialog, return to main menu
    main_menu
  fi
}




# Remove package with pagination
remove_package() {
  while : ; do
    search_term=$(yad --entry --title="Remove Package" --text="Enter search term (leave blank to list all):" --center)
    installed_packages=$(dpkg --list | awk '/^ii/{print $2}' | grep -i "$search_term")
    package_array=($installed_packages)
    total_packages=${#package_array[@]}
    
    if [[ $total_packages -eq 0 ]]; then
      yad --info --title="Remove Package" --text="No packages found." --center
      continue
    fi

    packages_per_page=20
    total_pages=$(( (total_packages + packages_per_page - 1) / packages_per_page ))

    page=1
    while [ $page -le $total_pages ]; do
      start_index=$(( (page - 1) * packages_per_page ))
      end_index=$(( start_index + packages_per_page - 1 ))
      if [ $end_index -ge $total_packages ]; then
        end_index=$(( total_packages - 1 ))
      fi

      package_list=()
      for i in $(seq $start_index $end_index); do
        package_list+=("FALSE" "${package_array[$i]}")
      done

      user_choice=$(yad --list --radiolist \
        --title="Remove Package" \
        --text="Select a package to remove (Page $page of $total_pages):" \
        --column="Select" --column="Package" \
        "${package_list[@]}" \
        --width=400 --height=300 --center --separator=":" \
        --button="Previous:0" --button="Next:1" --button="Remove:2" --button="Cancel:3")

      case $? in
        0) # Previous
          if [ $page -gt 1 ]; then
            page=$(( page - 1 ))
          fi
          ;;
        1) # Next
          if [ $page -lt $total_pages ]; then
            page=$(( page + 1 ))
          fi
          ;;
        2) # Remove
          if [[ -n "$user_choice" ]]; then
            package_name=$(echo "$user_choice" | cut -d':' -f2)
            # Use pkexec for apt remove
            (
              output=$(pkexec bash -c "apt remove -y $package_name 2>&1")
              remove_status=$?
              yad --title="Package Management" --text="$output" --width=600 --height=400 --center --button="OK:0"
              if [[ $remove_status -eq 0 ]]; then
                yad --info --title="Package Management" --text="Package '$package_name' removed successfully." --center
                break  # Exit the while loop
              else
                yad --error --title="Error" --text="Failed to remove package '$package_name'." --center
              fi
            ) &
          else
            yad --error --title="Error" --text="No package selected." --center
          fi
          ;;
        3) # Cancel
          main_menu
          return
          ;;
      esac
    done

    # After handling one removal, continue to allow removing more packages
  done
}

# List all installed packages
list_installed_packages() {
  tmpfile=$(mktemp)
  dpkg --list | awk '/^ii/{print $2}' > "$tmpfile"
  yad --title="Installed Packages" \
      --text-info \
      --filename="$tmpfile" \
      --width=600 --height=400 \
      --wrap --center
  rm "$tmpfile"
  main_menu
}

# Start the main menu
main_menu

exit 0
