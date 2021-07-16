const users = [
  ["FULL NAME", "EMAIL"],
  ["FULL NAME", "EMAIL"],
];

users.forEach((user) => {
  var full_name = user[0];
  var email = user[1];
  var apiUrl =
    window.location.origin +
    "/api/v1/accounts/self/users" +
    "?user[name]=" +
    full_name +
    "&pseudonym[unique_id]=" +
    email +
    "&pseudonym[send_confirmation]=true" +
    "&pseudonym[force_self_registration]=true";

  $.ajax({
    type: "POST",
    url: apiUrl,
  });
});
